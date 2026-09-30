# Linux on HP OmniBook 5 Glymur

This repository tracks native Linux bring-up for the HP OmniBook 5 16-bf1xxx family using Qualcomm Snapdragon X2 / Glymur.

The working project target is:

    HP OmniBook 5 NGAI 16-bf1107nr
    D3ZN3UA
    Snapdragon X2 Elite X2E-84-100
    32 GB RAM
    16-inch OLED touchscreen

The live WMI capture reports the 16-bf1xxx family; the BIOS Main page additionally shows product number `D3ZN3UA#ABA`, confirming the documented D3ZN3UA target family.
16-bf1xxx is the HP hardware family covered by the service documentation.

The board device tree is `dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts`. The SoC is
the Mahua die, described by Qualcomm's `mahua.dtsi`, which builds on
`glymur.dtsi`.

## Project Philosophy

- Evidence-first bring-up
- No foreign DTB will be booted on the target
- Other Glymur device trees may be studied as references only
- Machine-specific properties must be derived from the target machine or applicable documentation
- Unknown values must remain unknown rather than being guessed

Current phase: comparing Qualcomm's Snapdragon X2 kernel and Debian image recipes with this HP's ACPI evidence. Qualcomm validates its preview on reference hardware, not this laptop. Two Ubuntu ARM64 ACPI captures confirm CPU, PCIe, NVMe, xHCI, camera, and installer storage, while I²C/input remain unavailable. The pinned Qualcomm kernel and CRD DTB compile in WSL but have not been booted on this machine. Fedora ARM64 remains the intended installed OS. See `docs/qualcomm-preview-review-2026-09-25.md` and `docs/qualcomm-acpi-gap-2026-09-25.md`.

## CURRENT GATE

**2026-09-30, kernel `-12`, port-swap retest: the crash fix holds, but
full/low-speed USB-C enumeration is still broken.** Two more
`check-usb.sh` runs with the charger and mouse swapped between the two
USB-C ports produced zero crashes across four host-mode role-switches,
confirming the `-12` fix (below) holds under real plug/swap cycling. But
the mouse receiver failed identically every time (`error -71`, `device
descriptor read/64`) on both ports — the same signature as before the
eUSB2 repeater work started. The repeaters still identify correctly, but
that was never proof they fix low-speed signaling, and this confirms
they don't (yet). The crash and the original full/low-speed enumeration
bug are two separate problems: only the crash is fixed. Next step is
checking the repeater's tuning/mode-setting registers against
`phy-qcom-eusb2-repeater.c`, per `docs/usb-c-ports-2026-09-29.md`. See
`docs/usb-dwc3-crash-2026-09-30.md`.

**2026-09-30, kernel `-12`: the dwc3 crash and battery hang both look
fixed.** Same tests re-run after installing a new kernel: zero `Internal
error`/`refcount_t: underflow`/`cannot create duplicate filename`
occurrences anywhere in the boot log, and both `usb_0` and `usb_1`
completed a host-mode role-switch cleanly — the exact transition that
crashed twice before on `-11`. The battery manager reads a real `18`
percent instantly, no timeout, for the first time since it started
hanging this session. GPU/Mesa and the EC both still check out fine.
Root cause and fix aren't independently confirmed from this checkout's
own commits, but the two previously-reliable triggers both completing
cleanly is a strong signal. Worth a few more ordinary-use boots before
calling it closed. See `docs/usb-dwc3-crash-2026-09-30.md`.

**2026-09-30, kernel `-11`: the USB-C crash is deterministic — it
reproduced again on a fresh reboot.** After the first crash (below),
rebooting did not help: within ~8 minutes, `check-usb.sh` hit the
identical signature again, this time unambiguous — `refcount_t:
underflow; use-after-free` tearing down a USB-C controller's xhci device,
then the next probe on that corrupted `software_node` dereferences
leftover string data as if it were a pointer, and faults. This is a real,
reproducible kernel bug in `software_node` registration/refcounting for
the dwc3 USB-C controllers on this consolidated test DTB — it will keep
happening on every role-switch cycle until fixed at the kernel level.
Mesa/GPU and the EC both ran clean on the fresh boot beforehand, so
this stays isolated to the USB-C role-switch path. See
`docs/usb-dwc3-crash-2026-09-30.md`.

**2026-09-30, kernel `-11`, first occurrence: a USB-C role-switch hit a CPU
exception, `usb_1` and the battery manager both still broken.** A
wireless mouse receiver enumerated cleanly on `usb_1`, then ~13 s later a
genuine `SP/PC alignment exception` (a jump to a garbage program counter)
hit inside `xhci_plat_probe()` during a dwc3 role-switch for that same
controller. `usb_1` has had no bound `xhci-hcd` since, confirmed across
three `check-usb.sh` runs afterward. A real boot-time bug traces back to
it: `sysfs: cannot create duplicate filename .../software_node` for
*all three* dwc3 controllers (not just the USB-C ones), which also broke
`pmic_glink`'s device-links to the Type-C PHYs — the likely source of the
stale fwnode the crash dereferenced. Within the same ~26 s window UCSI
failed and recovered on its own; the battery manager failed the same way
it has before and has **not** recovered — still hung now, the same false
"0%" as the earlier hang. USB-A and the camera, on separate controllers,
kept working throughout, and GPU/Mesa and the EC (tested minutes earlier)
were unaffected — this is isolated to the USB-C role-switch path, not a
general meltdown. Needs a real kernel fix; a reboot is the only way back
to a fully working system right now. See
`docs/usb-dwc3-crash-2026-09-30.md`.

**2026-09-30, kernel `-10` booted: backlight timeout and independent mute
LEDs confirmed; the hotkey event line is silent.** Both `-10` corrections
are now proven live, not just argued from ACPI tables: the keyboard
backlight timeout (`30s`/`3min`/`always`) behaves exactly as set, and the
two mute LEDs are genuinely independent — `-9`'s "LED 8 lights both keys"
was residual state left over from a prior Windows session (the EC's LED
state really does persist across reboots and across OSes, confirmed).
New open item: the EC's own hotkey event line (GPIO 66) produced no
events at all in a 30 s capture across F6/F9/F11/F5/Fn — only the generic
keyboard HID path reported anything. The USB-C repeater fix still hasn't
been retested against an actual full/low-speed device (nothing was
plugged into either USB-C port this boot). See `docs/ec-2026-09-30.md`.

**2026-09-30, kernel `-10` staged: EC corrections and hotkeys.** On `-9`
the fan and thermistors worked. The keyboard-backlight command turned out
to be HP's backlight *timeout* (30 s / 3 min / always, as Windows offers),
not the level, which only F5 sets inside the EC; `-10` exposes it as
`kbd_backlight_timeout` and no longer claims a backlight LED. The
"LED 8 lights both keys" reading is unproven: F9's LED was already on
before its own test. `-10` also takes the EC's event line (GPIO 66), so
F9 reports mic mute and F11 its programmable key, as on Windows. The next
boot also installs lscpu from util-linux PR #4657. **Test:**
`install-from-usb.sh`, boot "GPU and USB-A test", `sudo bash
~/check-ec.sh` (interactive), and a mouse in a USB-C port for the
repeater. See `docs/ec-2026-09-30.md`.

**2026-09-30, kernel `-9` booted: EC driver confirmed live, mixed
results.** `hp-omnibook-5-ec` binds cleanly. Fan and thermistor readings
are real and stable (idle fan, 31-36 °C across four sensors). The
keyboard-backlight write doesn't visibly change anything (owner-confirmed
still off after setting all three levels) — likely missing an OS-control
flag the mute-LED path already sends. The mute LEDs are real hardware but
not the assumed 1:1 mapping: `platform::micmute` (LED 9) correctly lights
only F9, but `platform::mute` (LED 8) lights *both* F6 and F9 together.
Also confirmed live this boot: the eUSB2 repeater fix works (`parent PMIC
subtype 0x5f v2.0` on both USB-C ports, no more `error -71`), and the
camera enumerates (`30c9:00d9 HP True Vision FHD Camera`,
`/dev/video0`-`3`). See `docs/ec-2026-09-30.md`.

**2026-09-30, kernel `-8` staged: eUSB2 repeaters for the USB-C ports, the
camera's controller, and the new qcom-next base.**
- **Full/low-speed USB.** Qualcomm's Mahua/Glymur CRD drives each USB-C
  port's eUSB2 PHY through an SMB2370 repeater on SPMI bus 2 (SID 9 →
  `usb_0`, SID 10 → `usb_1`). HP's power votes for those ports include the
  repeaters' two rails (L15B 1.8 V, L7B 3.072 V). Without a repeater node,
  Linux never puts the repeater in host mode. On the ACPI boot, where the
  firmware's setup is untouched, full speed worked (a receiver at 12 Mb/s
  on USB-A).
    - The USB test DT now declares the repeaters.
    - A new driver check (`upstream/qcom-next/0003`) makes each repeater
      verify its PMIC is an SMB2370 before anything writes to it. A wrong
      guess costs that USB-C port's data for the boot, never a write to the
      wrong PMIC.
    - USB-A is unchanged.
- **Camera.** `usb_hs` (the internal camera's controller) is enabled, host
  only.
- **Base.** qcom-next moved to `6b4daa845239` (Nord only); the eDP PHY
  backports were re-ported and Glymur's code is byte-identical.
- **Test:** a mouse in each USB-C port, `check-usb.sh`. See
  `docs/eusb2-repeater-2026-09-30.md`.

**2026-09-30, camera controller identified; audio stopped deliberately at
evidence limits.** The owner asked about the camera (works on ACPI, not
on device-tree boots) and other unsettled bits (keyboard-backlight OS
control, mute LEDs). The camera is a real USB2 peripheral on its own
controller, `usb_hs` (ACPI `QCOM0FEF`), now fully decoded from HP's DSDT
— memory, interrupts, one GPIO, and a PEP rail-vote table matching the
same rails already used successfully today — a good next USB target,
same low risk as the USB-A/USB-C work (worst case: doesn't enumerate).
Not staged yet. See `docs/camera-usb-controller-2026-09-30.md`. Audio's
internal speaker/mic path stopped short of any DT work on purpose: real
but unidentified GPIOs turned up on the audio ACPI devices, and a wrong
guess there risks damaging a speaker or mic, not just failing to work —
a different risk class than GPIO guesses elsewhere in this project. See
`docs/audio-acpi-tree-2026-09-30.md`. Keyboard backlight and the mute
LEDs remain blocked on the same larger, known gap as the fan: the EC
(IC10) has no DT node or driver at all yet — not a quick GPIO fix, a
separate driver-stack undertaking.

**2026-09-30, the battery manager hung mid-session (not a real
battery-empty event).** From 12:21:12, every `qcom-battmgr-*` property
failed with `-110` continuously for 14+ minutes, GNOME showed a false
"0%". ADSP/CDSP stayed running; UCSI (a different client on the same PMIC
GLink transport) kept working the whole time. No PDR/servreg down event
was ever logged for the stuck service — looks like a firmware-side
battery-manager hang, not a Linux bug. Don't trust the percentage if this
recurs; plug in the charger regardless of what's shown. See
`docs/battmgr-hang-2026-09-30.md`.

**2026-09-30, USB full/low-speed devices fail on all three host ports —
an eUSB2 repeater gap, not a bad port.** The owner's mouse was tried on
`usb_0` (hinge), `usb_1` (away from the hinge) and USB-A this boot, and
failed identically on all three — `error -71`, escalating to `WARN:
invalid context state for evaluate context command` — including on USB-A,
which has cleanly enumerated a SuperSpeed stick on every prior boot, and
on `usb_1`, which enumerated that same stick on its SuperSpeed side in
this very boot. High-speed and SuperSpeed work everywhere tried;
full-speed and low-speed fail everywhere tried. This is the predicted,
deliberately-undeclared eUSB2 repeater gap confirmed board-wide: all
three controllers share the same `qcom-m31eusb2-phy` design, and native
eUSB2 without a repeater is typically high-speed-only. Not something a DT
retry fixes without more hardware evidence (a real repeater IC HP's ACPI
doesn't describe). See `docs/usb-c-ports-2026-09-29.md`.

**2026-09-30, GPU bring-up done: confirmed clean on kernel `-7`, the real
desktop.** Booted `7.3.0-rc2-glymur-7`. Zero corruption, and the first
boot in this whole investigation with no `fd_pipe_new2`/`unsupported GPU
id`/software-fallback lines anywhere — `gnome-shell` itself is on the real
Mesa, not just test programs. `glmark2` (GPU default, no overrides) scores
**11570**, a ~400× jump from `-6`'s corrupted default (29): that low score
was the GPU stumbling over out-of-range GMEM accesses every frame, not
just visible noise. No GPU faults or hangs. Root cause, fix, and
confirmation now all line up: the kernel told userspace the wrong GMEM
size for a 3-slice Adreno X2-85; `upstream/qcom-next/0002` corrects it.
Worth upstreaming — qcom-next and mainline msm still have this bug. See
`docs/gpu-corruption-2026-09-30.md`.

**2026-09-30, later still still (kernel `-7` installed):** `install-kernel.sh`
and `install-gpu-firmware.sh` run natively on the SSD install (no WSL/
Windows involved). `/boot/vmlinuz-glymur` and `/boot/glymur-dtb` now point
at `7.3.0-rc2-glymur-7` and its device trees; the previous kernel and DTBs
stay reachable as `.old`. Mesa `26.2.3-2` (already switched on
system-wide) and the cpufreq boot service were already current, so
nothing else needed reinstalling; `charging-watch.sh`, `check-usb.sh` and
`gpu-corruption-test.sh` were refreshed from the USB's newer versions.
**Next: reboot into "device tree (GPU and USB-A test)"** (no GRUB change
needed) and check whether the desktop itself renders clean — the real
test of the GMEM fix, beyond `gpu-corruption-test.sh`'s kmscube-only
confirmation on `-6`.

**2026-09-30, later still (GMEM root cause confirmed exactly as
predicted, without booting `-7` yet):** `gpu-corruption-test.sh`'s second
run, still on kernel `-6`: `sysmem` and `FD_MESA_GMEM=16515072` (the
correct 15.75 MB) or half of that all render clean; the GPU's *default*
path — Mesa trusting the kernel's wrong 21 MB — is the only corrupted
case. Matches the prediction exactly. An over-estimate of GMEM causes the
corruption; an under-estimate is safe. Kernel `-7` itself (which reports
the correct value without any override) is built and staged but not yet
booted on hardware. See `docs/gpu-corruption-2026-09-30.md`.

**2026-09-30, later (kernel `-7`: the GPU corruption's root cause is in
the kernel; log review corrects the USB-C picture):**

- **GPU corruption: root cause found, fix built.** msm tells Mesa the
  X2-85 has 21 MB of GMEM, the size for all four slices, but this part
  runs three. Qualcomm's KGSL reports 21 MB / 4 × 3 = 15.75 MB. Mesa put
  tiles and its caches past the end of real GMEM, so only `sysmem` was
  clean. `-7` adds `upstream/qcom-next/0002`, which reports GMEM for the
  active slices (OpenGL and Vulkan both). `gpu-corruption-test.sh` now
  tests it on either kernel with Mesa's `FD_MESA_GMEM` override. See
  `docs/gpu-corruption-2026-09-30.md`.
- **USB-C, corrected** (`docs/usb-c-ports-2026-09-29.md`):
    - port0 ending as `device` was the charger plugged into it, which is
      correct;
    - the mouse that failed on port0 was low-speed and the hub that worked
      on port1 was high-speed, so a speed problem (eUSB2 repeater) fits as
      well as a port problem. Swap them to tell;
    - every host-to-device role switch logs a kernel WARN (Type-C partner
      links removed out of order);
    - charging through the hub turned the laptop into the USB device and
      the stick disappeared (no data-role swap);
    - SuperSpeed on USB-C is still untested.
- **`charging-watch.sh` fixed:** its trace reader could outlive it and
  trip the hung-task detector.

**2026-09-30 (three results in from kernel `-6`: charging fixed, USB-C data
works on one port, GPU corruption isolated to GMEM tiling):**

- **Charging: fixed.** `charging-watch.sh`, ~5.5 minutes of plug/unplug on
  both ports, logged zero "undefined port" lines (every prior run had one,
  then total silence). Every plug/unplug now tracks correctly in sysfs and
  the firmware's own polled status, battery `Charging`/`Discharging`
  transitions included. See `docs/usb-c-ports-2026-09-29.md`.
- **USB-C data: one port confirmed, one unsettled.** Connector 1 (away
  from the hinge) works as host: `partner=yes`, PD, and a real USB 2.0 hub
  + mass-storage device enumerated and read at 480 Mb/s. Connector 0
  (hinge side) shows a partner but churned through a failed host-mode
  enumeration (`error -71` ×3) before settling as `device` — needs a
  retest with a known-good USB-C drive to isolate. See
  `docs/usb-c-ports-2026-09-29.md`.
- **GPU corruption: isolated to `sysmem` (GMEM tiling).**
  `gpu-corruption-test.sh`'s first run: only the two cases including
  `FD_MESA_DEBUG=sysmem` were clean; linear scanout, `noubwc` and `nolrz`
  alone all stayed corrupted. Points specifically at Mesa's 3-slice
  GMEM/bin-layout tiling, not UBWC compression or LRZ. Workaround:
  `sudo mesa-glymur-run --system off`, or force `FD_MESA_DEBUG=sysmem`.
  Worth reporting upstream. See `docs/gpu-corruption-2026-09-30.md`.

**2026-09-30 (GNOME on the GPU, but corrupted):**

- **What happened.** With `-6` and Mesa `26.2.3-2` system-wide, GNOME
  composites on the Adreno X2-85 (About: "Adreno X2-85"). The screen shows
  noise bands and block-shaped garbage.
- **What isn't the cause.** The kernel's UBWC, GMEM and slice setup match
  Qualcomm's own KGSL driver, and the display was clean with software
  rendering.
- **Suspect.** Mesa's barely tested 3-slice gen8 path.
- **Next.** On a text console (Ctrl+Alt+F3), run `sudo apt install
  kmscube` and then `bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/gpu-corruption-test.sh"`.
  It runs a GPU cube with compression, LRZ and GMEM tiling switched off
  one at a time, asks whether each looked clean, and logs the kernel's
  GPU messages.
- **Clean desktop meanwhile.** `sudo mesa-glymur-run --system off`, then
  reboot. See `docs/gpu-corruption-2026-09-30.md`.

**2026-09-30 (kernel `-6`: the charging fix, USB-C ports and system-wide
Mesa, built; waiting for the USB stick to stage):**

- **Kernel `7.3.0-rc2-glymur-6`.** Same qcom-next base (re-fetched: the
  tip is still `e428097a36d`; mainline has nothing newer for these
  drivers). It adds one patch: `pmic_glink_altmode` now acknowledges port
  notifications for ports without a connector node. The missing
  acknowledgement is the likely cause of charging stopping after the
  first unplug (`docs/usb-c-ports-2026-09-29.md`).
- **Device tree ("GPU and USB-A test" entry, shipped in the `-6`
  package).** Both USB-C ports are described from HP's tables: connector
  0 (hinge side) → `usb_0`, connector 1 → `usb_1`, each with its eUSB2
  and QMP PHYs. The firmware's notifications are now carried out and
  acknowledged, and the USB-C ports can carry data.
- **Mesa `26.2.3-2`.** Adds llvmpipe on Ubuntu's LLVM 21.
  `install-from-usb.sh` turns on `mesa-glymur-run --system on`, a
  dynamic-linker switch that should bring gnome-shell onto the GPU.
  `check-mesa.sh` shows which libraries it actually loaded
  (`docs/mesa-x2-85-2026-09-29.md`).
- **Next:**
    1. Once `-6` and Mesa are staged, from "device tree (GPU and USB-A
       test)" (its USB-A port works) run `install-from-usb.sh`.
    2. Reboot into the same entry.
    3. Run `check-mesa.sh`, `check-usb.sh` (with USB-C and USB 2.0
       devices plugged in) and `charging-watch.sh`.

**2026-09-29 (charging lead: unacknowledged port notifications; fix
staged):**

- **Re-timed charging run.** Re-timed with kernel timestamps (the trace
  lines were read late), `charging-watch.sh`'s run shows the 41 W session
  ending at 22:14:55. In the same second the kernel logged
  `pmic_glink_altmode: notification on undefined port 1`. After that, the
  firmware's own connector status never showed a connection again on
  either port.
- **Why.** Our `pmic-glink` node has no connector nodes, and
  `pmic_glink_altmode` only sends the firmware `ALTMODE_PAN_ACK` for
  defined ports. No notification had ever been acknowledged.
- **Staged.** The "device tree (GPU and USB-A test)" DTB on the USB now
  declares two bare `usb-c-connector` nodes (DTB-only, `398b335e…`).
- **Next boot of that entry:** run `sudo bash ~/charging-watch.sh` and
  plug, unplug and replug on both ports. See
  `docs/usb-c-charging-2026-09-29.md`, last section.
- **eDP.** The one blank boot matches a known post-fix eDP link-training
  intermittency (Zenbook A16: `-110` in about 1 of 3 boots). It is
  probably not caused by USB-A (`docs/usb-a-bringup-2026-09-29.md`).

**2026-09-29 (charging: real sessions, unstable negotiation):**
`charging-watch.sh`'s first live run (kernel `-5`): the owner plugged in
about a minute before starting it, and by the time it started a real 41 W
PD session was already up on port1 — proof the port and negotiation can
work for real. After it dropped on its own about a minute later, ~5.5
minutes of plugging/unplugging both ports left sysfs *and* the
firmware's own directly-polled connector status both flat at disconnected
— but two genuine `ucsi_connector_change` hardware interrupts fired
anyway, one per port, each already collapsed back to `connected=0` by the
time it was read. Together with a stray +45.6 W heartbeat read right after
a disconnect, this points at unstable/collapsing negotiation rather than a
missing driver feature. See `docs/usb-c-charging-2026-09-29.md`.

**2026-09-29 (real GPU acceleration confirmed; GNOME's compositor still isn't
using it):** `check-mesa.sh` (Mesa 26.2.3, `/opt/mesa-glymur`) on the GPU
test DT: `mesa-glymur-run eglinfo -B -p gbm`/`-p surfaceless` and
`vulkaninfo` all report the real `Adreno (TM) X2-85` device (not a
fallback), `glmark2` scores 29, and devfreq genuinely ramps to 1.35 GHz
under load — this is real, working hardware rendering and compute, not
just a bound-but-idle GPU. Only GNOME's own compositor (`gnome-shell`)
still shows software rendering: the desktop-wide `environment.d` switch
hasn't taken effect for it across two attempts (once after a disruptive
`systemctl restart user@1000.service`, once after a clean full reboot with
the file genuinely present), even though `gnome-shell` runs as a proper
systemd user unit that should inherit it. Cause not yet found. See
`docs/mesa-x2-85-2026-09-29.md`.

**2026-09-29 (USB-A works; eDP is boot-to-boot flaky on that DT):** the
"device tree (GPU and USB-A test)" entry was booted twice back-to-back,
same DTB and kernel. First boot: everything worked together for the first
time — `usb_2`'s M31 eUSB2 and QMP combo PHYs both bind, and the boot
stick itself enumerates through the internal controller at 5000 Mb/s,
*and* the eDP panel was connected/enabled at 1920x1200 on the same boot.
Second boot, two minutes later: blank screen. Keyboard and the rest of the
system were alive (gdm/gnome-shell started normally, GPU bound) — this was
`msm_dp_ctrl_link_train_1_2` timing out (`ret=-110`) partway through
training, a different failure than the pre-backport `phy poweron failed`
bug, not a hang. Same DTB succeeding once and failing the next boot rules
out a deterministic DT regression; it looks like more of the same
boot-to-boot power/reference-clock marginality already seen in USB-C
charging. Next: reboot "GPU test" (no USB-A) a few times back-to-back to
see if eDP is equally flaky there, to tell a shared-reference-clock
interaction from a general one. See `docs/usb-a-bringup-2026-09-29.md`.

**2026-09-29 (hardware rendering and a USB-A test staged; charging re-read):**

- **Hardware rendering.** "Software Rendering" is a Mesa version gap:
  Ubuntu 26.04's Mesa 26.0.8 has no X2-85 entry, and Mesa **26.2**
  (`0xffff44070031`, both freedreno GL and turnip Vulkan) has one. Mesa
  26.2.3 is built as a normal user, hash-checked against its release notes,
  and staged on the USB. It installs under `/opt/mesa-glymur` beside
  Ubuntu's Mesa: per program with `mesa-glymur-run`, and for the whole
  desktop only after `mesa-glymur-run --desktop on`. See
  `docs/mesa-x2-85-2026-09-29.md`.
- **cpufreq at boot.** A boot service loads `scmi-cpufreq` only on device
  trees that carry the SCMI polling fix.
- **Charging.** The `-4` session's own capture shows the battery
  **charging at 40 W** over PD. Charging on the DT boot is intermittent,
  not absent, and `qcom-battmgr-ac`/`-usb` `ONLINE` do not track the
  charger. `charging-watch.sh` records the firmware's connector status and
  the UCSI tracepoints live. See `docs/usb-c-charging-2026-09-29.md`.

- **USB-A on device-tree boots (staged, untested).** A new entry, "device
  tree (GPU and USB-A test)", is the GPU test DT plus the right-hand USB-A
  port (`usb_2` in host mode and its two PHYs). HP's DSDT and PEP evidence
  map the port onto them. It needs no new kernel. If it works, installs
  from the stick no longer need an ACPI reboot. See
  `docs/usb-a-bringup-2026-09-29.md`.

Next:

1. Boot "device tree (GPU and USB-A test)".
2. If the stick shows up, run
   `sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/check-usb.sh"`,
   then `bash ".../install-from-usb.sh"` from the same directory. If it
   doesn't, run the installer from "ACPI, newest glymur kernel" instead.
3. Reboot into the same entry and run `bash ~/check-mesa.sh` on the
   desktop.
4. Run `sudo bash ~/charging-watch.sh`, then plug, unplug and replug,
   typing a note at each step.

**2026-09-29 (GPU and CPU frequency scaling both work, on the GPU test
DT):** booted kernel `7.3.0-rc2-glymur-5`'s "device tree (GPU test)" entry.
The Adreno X2-85 binds, loads GMU firmware (v5.2.38), needs no zap shader
(as on upstream Glymur boards), and `devfreq` actively scales it
310 MHz-1.35 GHz, with the display still live on the same boot. `modprobe
scmi-cpufreq` — which hung the laptop hard in lab run 1 — now falls back to
polling (the upstream SCMI completion-IRQ fix) and gives real frequency
policies up to 4.03 GHz. GL/Vulkan still show "Software Rendering": the
installed Mesa (`26.0.8`) has no hardware-table entry for this chip ID yet
— a userspace/Mesa version gap, not a kernel or DT problem. See
`docs/gpu-bringup-run1-2026-09-29.md`. Neither GPU nor cpufreq is carried
by the full/minimal DTs yet.

USB-C charging: five unplug/replug attempts on `-5` showed nothing in
sysfs or the kernel log, although the owner saw the charging LED light
once. The later entry above re-reads this with the `-4` capture.

**2026-09-29 (the eDP panel works):** kernel `7.3.0-rc2-glymur-4`
backports Qualcomm's posted v8 eDP PHY programming-sequence fix (Bjorn
Andersson, "phy: qcom: edp: Update v8 programming sequence", June 2026;
`patches/kernel/backports/`, `docs/edp-phy-backport-2026-09-29.md`) and it
works: booted on the **unmodified full DTS**, no `phy poweron failed`
anywhere in the log, link training succeeds on the first attempt at 2
lanes/2.7 Gb/s (the panel's own limit), `eDP-1` shows
`connected`/`enabled` at 1920x1200, and DP-AUX backlight control is live.
This is the first confirmed 2-lane 2.7 Gb/s training report for this
series (the only other public report, an ASUS Zenbook A16, trained at
5.4 Gb/s). Same boot: battery/AC/USB-C power supplies, Bluetooth, Wi-Fi,
and ADSP/CDSP all work; GPU stays safely disabled as designed; there is
still no audio, USB or TPM. See `docs/edp-display-working-2026-09-29.md`
and `docs/edp-phy-backport-2026-09-29.md`. The plain
"device tree (full)" entry (no `drm.debug`) also brings the display up.
USB-C charging does not work yet (cause open,
`docs/usb-c-charging-2026-09-29.md`). Next: audio (SoundWire/LPASS; the
ADSP is already up). Other upstream patches
worth taking next (PUSH_IDLE reset fix, SCMI polling for cpufreq, USB
votes) are in `docs/upstream-patch-survey-2026-09-29.md`.

**2026-09-29 (lane/rate mismatch ruled out; the fault is in the PHY
driver):** the boot-time eDP 2-lane test (below) came back dark. Its
journal shows the panel's own DPCD ceiling is exactly 2 lanes at 2.7 Gb/s —
the same limit the test DTB declares — so msm was never being held back by
the device tree. The failure is `phy phy-faac00.phy.2: phy poweron failed
--> -110`, thrown by the PHY driver itself before link training starts,
identical to the failure the display lab found independently
(`docs/display-lab-run3-2026-09-28.md`) in its own instrumented copy of the
driver. Two different code paths now show the same fault, so it is inside
`phy_qcom_edp_phy_power_on_v8()`/PLL configuration in
`drivers/phy/qualcomm/phy-qcom-edp.c`, not fixable from the DTS. Leading
hypothesis: a 10-register PLL coefficient mismatch between the driver's
hardcoded 2.7 Gb/s table and the firmware's live PLL values. The lab
already has (uncommitted, unbuilt) instrumentation — `lab_fw_pll` — that
substitutes the firmware's PLL values at power-on and four variants (W1-W4)
to test it; that needs a WSL rebuild and a fourth lab run. See
`docs/edp-2lane-test-run1-2026-09-29.md`.

**2026-09-29 (eDP 2-lane test staged):** the lab's display phase hung the
laptop twice, so the firmware's link configuration is now tested at boot
time with the stock drivers. The USB entry "Ubuntu on SSD: eDP test, 2
lanes (device tree)" boots the `-3` kernel with the full DT limited to 2
lanes at up to 2.7 Gb/s, the configuration the firmware runs. msm's retries
never reach it from the full DT's 4 lanes at up to 8.1 Gb/s. It adds DRM
DP debug logging. If the panel lights, the two endpoint properties go into
the full DTS. If it stays dark, wait three minutes before powering off, and
read `journalctl -k -b -1` from the next boot. The GRUB menu was also
cleaned up to 9 entries. See `docs/edp-2lane-test-2026-09-29.md`.

**2026-09-28 (first DT boots):** the minimal DT is the new working
baseline — CPUs, NVMe, native DT input, thermal, cpuidle and Wi-Fi, on the
firmware framebuffer. The full DT reaches userspace cleanly, with HP's
signed ADSP/CDSP firmware attached over the SoCCP, but the eDP panel stays
dark: an eDP link-training failure at the DP PHY (`ret=-11`, "max v_level
reached"), not the GPU-component issue the prior review already guarded
against. The two-rail regulator fix drafted that day is reverted (see
`docs/display-lab-2026-09-28.md`). The first lab run (kit staged from the USB, run on the lab boot) captured
the firmware's link and finished the Bluetooth test, but the laptop hung in
phase 4 when the lab loaded `scmi-cpufreq`, so no display variant ran. The
firmware drives the panel on **2 lanes at 2.7 Gb/s; our DT declares 4 lanes**
(`docs/display-lab-run1-2026-09-28.md`). The fixed kit is at
`~/glymur-lab-kit`. Next: on a display-lab boot, `sudo bash
~/glymur-lab-kit/start-lab.sh` again (phase 5 runs the DPCD dump and ten
variants), and try `data-lanes = <0 1>` in the full DT regardless. A DT boot still has no USB, GPU or audio. Keep booting the minimal DT
otherwise.
See `docs/device-tree-first-boot-2026-09-28.md` and
`docs/device-tree-review-2026-09-28.md`.

**2026-09-27 (first boot):** the qcom-next boot kernel (`7.3.0-rc2-glymur`)
is installed and booted on SSD partition 5, from the USB's GRUB (the SSD's
EFI partition stays untouched). Input, the EC bus/thermal/fan, and CPU idle
carry over from the stock-Ubuntu results, and Wi-Fi now fully associates.
USB-C, the native GPU, Bluetooth, audio, battery/AC/RTC, TPM, and CPU
frequency scaling remain gated behind the device-tree path. Next: fix or
work around the chrony/RTC ACPI-error journal flood, then continue the
device-tree work for the remaining subsystems. See
`docs/qcom-next-first-boot-2026-09-27.md` and
`docs/fan-thermal-windows-2026-09-27.md`.

**2026-09-26 (after reboot):** CPU core idle works with a BIOS-gated DSDT
`_OSC` fix, and the EC bus works over GPI DMA (thermal zones now read).
The remaining power gaps are CPU frequency scaling (no `_CPC`), cluster
idle, battery (PMIC GLink) and the GPU; these point to the device-tree
path. See `docs/cpuidle-and-ec-bus-results-2026-09-26.md`.

**2026-09-26 (live workstation):** the EC bus needs the QUP1 GPI DMA
engine. A derived ACPI GPI driver binds it and its command path works, but
the first live test lost the channels to `async_tx`. Retry after a reboot;
see `docs/ec-gsi-live-test-2026-09-26.md`.

**2026-09-26 (run 2):** the keyboard, touchpad, and touchscreen work under
the stock Ubuntu live kernel with two out-of-tree ACPI modules, and Wi-Fi
scans with HP board data. See `docs/acpi-input-results-run2-2026-09-26.md`.
Remaining gaps:

- the EC bus, which needs GPI DMA;
- battery and AC, and USB-C, via ADSP/PMIC GLink;
- GPU, audio, Bluetooth, suspend.


**2026-09-26:** a staged live-USB test loads two out-of-tree ACPI modules,
for GPIO/PDC interrupts and GENI I²C, into the stock Ubuntu kernel to bring
up the keyboard and touchpad. See `docs/acpi-input-test-2026-09-26.md` and
the audit in `docs/repository-audit-2026-09-26.md`, which supersedes the
clock-hazard reasoning in the next paragraph for qcom-next. Battery, AC, and
USB-C share one missing path: ADSP, then PMIC GLink, then the ABD
GenericSerialBus region.

Previous gate:

The HP UEFI/ACPI path reaches Linux userspace, but Ubuntu registered no I²C adapter. The `i2c_qcom_geni` module loaded without binding any of the five HP `QCOM0F10` controllers; Qualcomm's reviewed `qcom-next` driver also lacks that ACPI ID. Its clock and wrapper assumptions make an ID-only patch unsafe. The HP UCSI ACPI object reported `status=0`, with no USB-C class device. Trace and validate both resource paths before another target boot. Do not flash Qualcomm reference images or load another board's DTB.
