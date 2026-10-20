# HP OmniBook 5 16-bf1xxx: board layer

Everything specific to this laptop lives here or is referenced from here.
The kernel patches under `patches/kernel/upstream/` and
`patches/kernel/glymur-bringup/` contain mechanisms only; the values below
switch them on for this board.

| Item | Where | Why it is board-specific |
|---|---|---|
| Kernel command line | `kernel-cmdline.conf` | Pins and I²C controllers proven on this machine |
| DSDT `_OSC` override | `scripts/linux/glymur-dsdt-osc-fix.py` (output private, BIOS-gated) | Works around an HP BIOS F.06 AML bug |
| Wi-Fi board data | `scripts/linux/ath12k-board-add.py` (output private) | HP subsystem `103c:8ef3` needs Windows' `bdwlan_qcc2072_1p0_ncm820A.elf` |
| Firmware for ADSP/CDSP/GPU, Bluetooth, Wi-Fi; audio calibration | `firmware/` (HP's driver pack, unmodified; `firmware/README.md`) | HP-signed images and HP's data |
| AudioReach topology (in test) | `audio/MAHUA-HP-OmniBook-5-16-bf1xxx.m4` | Stereo speakers on the WSA path and two DMICs on the VA path (`docs/audio-headset-path-2026-10-17.md`); derived from `linux-msm/audioreach-topology`'s `MAHUA-LENOVO-ThinkPad-T14s-Gen7.m4` without the DisplayPort sinks, the same, apart from comments, as its `GLYMUR-ASUS-Zenbook-A14-UX3407NA.m4`. Built with that repository's m4 includes and `alsatplg`; named after the sound card model, as there, and installed as `qcom/glymur/HP/omnibook-5-16-bf1xxx/MAHUA-HP-OmniBook-5-16-bf1xxx-tplg.bin` with a link at `qcom/glymur/MAHUA-HP-OmniBook-5-16-bf1xxx-tplg.bin`, the name the kernel requests |
| ALSA UCM profile (in test) | `audio/ucm2/` | Selected by the card's long name (`conf.d/glymur/HP-HPOmniBook5Laptop16_bf1xxx-ConfigID-8F47.conf`); based on alsa-ucm-conf's ASUS Zenbook A14 profile (the same two WSA884x and two DMICs), with the WSA-macro sequences Ubuntu 26.04 lacks copied from upstream; devices named "Internal Speakers" and "Microphone Array"; mute switches bound to the F6/F9 LEDs as in alsa-ucm-conf's ThinkPad T14s profile (`docs/audio-mute-leds-2026-10-20.md`) |
| WirePlumber names (in test) | `audio/wireplumber/` | Names the card after Qualcomm's Windows driver ("Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio Device") and its two devices as Windows does; installed to `/etc/wireplumber/wireplumber.conf.d/` |

## Kernel command line

`kernel-cmdline.conf` holds the module parameters:

- `glymur_acpi_gpio.enable=1 glymur_acpi_gpio.pins=3,51,66,67,92` enables
  these TLMM pins:

  | GPIO | Use |
  |---:|---|
  | 3 | Touchpad interrupt (PDC pin 896) |
  | 51 | Touchscreen interrupt |
  | 66 | EC events (PDC pin 768) |
  | 67 | Keyboard interrupt (PDC pin 704) |
  | 92 | Lid (PDC pin 960, also the `LIDR` OpRegion) |

- `i2c_qcom_geni.acpi_buses=0xb80000,0xb90000,0xa80000,0xa84000` binds these
  controllers:

  | Controller | Device |
  |---|---|
  | I2C1 | Keyboard `QTEC0001` at 0x3A |
  | I2C5 | Touchpad `ELAN0189` at 0x15 |
  | I2C9 | Touchscreen `ELAN2513` at 0x10 |
  | IC10 | EC at 0x76, over GPI DMA |

  I2C6 (SAR sensors and `QCOM0FC6`) is deliberately left out: it has never
  been read.

- `systemd.tpm2_wait=0`: the firmware publishes an ACPI `TPM2` table, but
  its start method (9) has no Linux driver and no `MSFT0101` device exists.
  systemd's TPM2 generator therefore waits for `/dev/tpm0` and
  `/dev/tpmrm0` and times out after 90 s on every boot (live inventory
  journal, 2026-09-26). The parameter stops it waiting. Drop it once a TPM
  driver binds.

Evidence for every value is in `docs/acpi-input-results-run2-2026-09-26.md`,
`docs/cpuidle-and-ec-bus-results-2026-09-26.md`, and
`docs/qcom-next-port-and-lid-2026-09-26.md`.
