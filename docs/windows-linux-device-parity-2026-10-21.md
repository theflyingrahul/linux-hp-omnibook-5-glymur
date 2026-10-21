# Windows devices against Linux, October 21, 2026

The 280 devices Windows enumerated on this laptop (Day-0 capture of
2026-09-14, `public/pnp/devices.tsv`, all `CM_PROB_NONE`) checked against
the running system: kernel `7.3.0-rc4-glymur-15`, test device tree, boot of
2026-10-21. `scripts/linux/map-windows-devices.py` classifies every Windows
device; the per-device result is `captures/2026-10-21-device-parity/
windows-vs-linux.tsv`, the Linux state it was checked against is
`linux-state.txt` in the same directory.

States: **working** (bound and exercised), **visible** (bound or running,
nothing exercised), **partial**, **failing**, **absent** (no Linux device).
Another 107 of the 280 are Windows-only (Hyper-V, RRAS, print queues,
volumes, audio effects, ACPI plumbing that a device-tree boot does not
have) and are listed as `n/a`. The other 173:

| State | Devices |
| --- | --- |
| working | 95 |
| visible | 40 |
| partial | 26 |
| absent | 8 |
| failing | 4 |

## By function

| Function | Windows device | Linux | State |
| --- | --- | --- | --- |
| CPU | 12 Oryon cores, 3 containers | 12 CPUs, SCMI cpufreq, cluster idle used | working |
| GPU | Adreno X2-85 | `adreno` bound, `/dev/dri/renderD128`; needs Mesa 26.2 | working |
| Display | Integrated monitor (ATNA60KJ02-0) | eDP, DP AUX backlight | working |
| Storage | Samsung NVMe | `nvme` on pcie5 | working |
| Wi-Fi | FastConnect C7700 / QCC2072 | `ath12k`, `wlo1` up | working |
| Bluetooth | UART transport, adapter | `hci0` up on the GENI UART, A2DP plays; RF calibration file `ornbcscal11.bin` missing | working |
| Bluetooth audio offload | `QCOM0FEA` ACX | not used (host A2DP instead) | absent |
| Keyboard, touchpad, touchscreen | `QTEC0001`, `ELAN0189`, ELAN2513 | `i2c_hid_of` on i2c 0, 4, 8; all tested | working |
| Camera | True Vision RGB, IR | `uvcvideo`; RGB and IR frames captured | working |
| Camera DFU | USB interface | no driver, not needed | absent |
| Microphones | Microphone Array | DMIC capture records a real signal | working |
| Speakers | Speakers (ACX static endpoints) | card and sink exist; both WSA884x amplifiers `UNATTACHED` | failing |
| Headset path | ACX headset render/capture, SDCA HID | jack input registers; not retested on `-15`; no SDCA function on the SoundWire bus | partial |
| Battery, AC | ACPI battery/AC, PMIC GLink | `qcom_battmgr`: battery 25 % discharging, AC offline at the time | working |
| Lid | ACPI Lid | `gpio-keys` with a lid switch | working |
| USB | 2 xHCI, 2 DWC3, root hubs | `xhci-hcd`, 4 `dwc3-qcom`; USB-A SuperSpeed stick in use | working |
| USB-C | UCSI, Type-C device | `ucsi_glink`, two typec ports; DisplayPort plug-in crashed the machine | partial |
| EC: fan, mute LEDs, HP services | ACPI Fan, HP Mute LED, HP Application Driver | `hp-omnibook-5-ec` did not bind (thermal zone name too long); fix is in the repo, needs kernel `-16` | failing |
| Thermal | 4 ACPI zones, 7 sensor devices | `qcom-tsens`, about 60 zones; the four EC thermistor zones missing | working |
| Power limits | PowerLimits `QCOM103F` | `qcom_spel` energy counters work; limits unreadable | partial |
| CPU/GPU/NSP policy devices | DCVS, parking, limits | SCMI cpufreq and GPU devfreq cover part; the rest has no counterpart | partial |
| Hexagon NPU, FastRPC | Hexagon NPU, CDSP, FastRPC | cdsp and adsp running, `/dev/fastrpc-*`; nothing run on the NPU | visible |
| Audio DSP | ADSP subsystem | adsp running with HP firmware | working |
| PCIe | 2 root complexes, 2 root ports | pcie4 (Wi-Fi), pcie5 (NVMe) | working |
| Buses | GENI I²C ×5, UART, SPI, SPMI, GPI, BAM | 4 of 5 I²C controllers, BT UART, SPMI, 3 GPI, BAM bound; SPI masters present | working |
| SoC plumbing | IOMMU, system cache, SMEM, IPCC, GLink, loaders | all bound | visible |
| Security | Secure processor, SCM, crypto engines | `soccp` attached, `qcom_scm`, `qcomtee` bound; crypto engines unused | visible |
| TPM 2.0 | Trusted Platform Module | no `/dev/tpm`; TPM2 start method 9 unsupported | absent |
| Sensors | Human presence, All-Ways Aware ×2, ADC | no IIO devices | absent |
| Video codec | (EVA `QCOM0FD7`) | `evacc` clock bound; Iris decode fails on `video_cc_mvs1_gdsc` | failing (Iris is not a separate Windows PnP entry here) |

## Not in the Windows list, but found on Linux

- **No RTC.** `rtc-efi` is bound but registers no `/sys/class/rtc` device,
  which is why the boot clock reads July 28 until NTP. Windows has `ACPI
  Wake Alarm`; `pmic_glink.rtc-glink` also has no driver.
- **No watchdog:** `17600000.watchdog` has no driver bound (`CONFIG_QCOM_WDT`
  is a module and not loaded).
- **Clock supplies:** `tcsrcc-glymur` logs 71 warnings of missing `vdda-*`
  supplies (dummy regulators). The rail rules in `CLAUDE.md` still apply:
  nothing was declared from CRD values.
- **Deferred probes:** none.
- **Hardware encryption and random:** `1dfa000.crypto` and `10c3000.rng`
  have no bound driver; `/dev/hwrng` exists.

## Reading the numbers

`working` here means the device is bound and either I or the owner used it
this session, or an earlier dated note proves it. The `visible` group is the
honest "bound, not exercised" bucket (mostly SoC plumbing). Where a Windows
device has no ACPI ID visible (this is a device-tree boot, `/sys/bus/acpi`
does not exist), the match is by function, not by ID, so a Windows
`Qualcomm(R) Bus Device` ×5 is matched to the GENI/GPI nodes by count and
role. The rules are in the script; edit them rather than the TSV.
