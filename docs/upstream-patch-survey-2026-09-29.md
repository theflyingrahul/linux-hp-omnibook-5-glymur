# Upstream Patches That Would Help, September 29, 2026

This is a survey of posted or merged work for Glymur (Snapdragon X2 Elite)
laptops, checked against our pinned qcom-next `a47c4c5aa`. The eDP PHY
series is already backported as kernel `-4`
(`docs/edp-phy-backport-2026-09-29.md`). Nothing below is applied yet.

| Priority | Patch | Why it matters here | In our tree |
|---|---|---|---|
| Before the next display test | "drm/msm/dp: skip PUSH_IDLE when the link training fails" (Jesse Casco, 2026-08-08; in linux-next as `e249a6e2a130`, 2026-09-13; approved by Dmitry Baryshkov) | On X2 Elite, a failed link training followed by `atomic_disable` writing PUSH_IDLE triggers a TrustZone force-stop of the remoteprocs, and the machine silently resets about 50 ms later. This is a plausible cause of the lab's silent hangs, and it protects any boot where training still fails. | No |
| High | "arm64: dts: qcom: glymur: use polling mode for SCMI transfers" (Jesse Casco, 2026-08-08) | The CPUCP firmware writes SCMI replies but never rings the mailbox doorbell, so `scmi-cpufreq` gets `-110`: the timeouts we saw in lab run 1. Adding `arm,no-completion-irq` to `/firmware/scmi` gave the Zenbook A16 cpufreq at 355 MHz to 4.45 GHz. Konrad Dybcio found building `qcom_cpucp_mbox` in (`=y`) also avoids it, which points to a timing bug. Our run 1 also hard-hung after the timeouts, which the report does not describe, so test this on its own. | No (`glymur.dtsi` has no `no-completion-irq`; `QCOM_CPUCP_MBOX=m`) |
| Medium, needed for USB | "arm64: dts: qcom: glymur: Add missing USB clock, power and bandwidth votes" (Greg Ociepka; merged 2026-08-31, `0f8d35f04a12`) | It adds `assigned-clocks`, `required-opps` and interconnects to the four USB3 controllers. Without them the power domain stays at SVS and no USB-DDR bandwidth is voted. | Only 1 of 4 controllers |
| Reference | "arm64: dts: qcom: Add HP OmniBook Ultra 14-kg0xxx" (Jason Pettit, 2026-08-30, under review) | A Glymur HP laptop with USB-C (DP alt-mode, PD), GPU, audio, ADSP/CDSP and RTC wired at board level. It is a pattern only: HP-specific values must still come from this machine. Its eDP is 4-lane up to 8.1 Gb/s. | n/a |
| GPU | "Devicetree support for Glymur GPU" v5 (May 2026) and the drm/msm A8xx batches | Our tree has the GPU nodes. We also need `CONFIG_CLK_GLYMUR_GPUCC` (off), the GPU/GMU enabled in our DT, and GMU firmware. The Zenbook reports a working GPU. | Partly |
| TPM | "Add TPM support via Qualcomm TEE TPM TA" v2 (2026-09) | Our tree already has `drivers/char/tpm/tpm_qcom.c` (`CONFIG_TCG_QCOM` off). Our DT boots log `qcomtee: Failed to get service! error: 11`. **Caution:** Windows' BitLocker uses this TPM, and systemd can create persistent keys in it. Research that before enabling anything. | Driver present, off |
| Low | "arm64/cpufreq: report and track …" (Oleg Keri, 2026-09) | Fixes frequency reporting above 4.2 GHz and the boost reference. It matters only once cpufreq works. | No |

## Other findings

- **eDP after the PHY fix.** The Zenbook A16 report (bprendie/omarchy-snapdragon
  issue #2) still saw a black screen with `-110` in about 1 of 3 boots.
  FixItFoundry/zenbook-a16-linux carries eDP `LINK_RATE_SET` patches for
  it. They are not posted upstream, and our panel uses that eDP 1.4
  rate-table path. Review them before relying on them.
- **Audio.** `glymur.dtsi` in our tree already has the LPASS, GPR and
  SoundWire nodes. The missing part is board wiring: codecs, speakers, the
  machine driver and topology. The Zenbook needed a UCM name symlink after
  that.
- **Wi-Fi.** The Zenbook uses the same fix we use: an ath12k `board-2.bin`
  rebuilt with the vendor `bdwlan_qcc2072_1p0_ncm820A.elf`.
- **Fan/EC.** The Zenbook has no Linux interface either; its EC runs the
  fan by itself.

## Sources

- https://ratatoskr.run/lkml/2026/08/17386996/t (PUSH_IDLE)
- https://ratatoskr.run/linux-arm-msm/2026/08/17387004/t (SCMI polling)
- https://ratatoskr.run/lkml/2026/08/17400692/t (USB votes)
- https://ratatoskr.run/lkml/2026/08/17480253/t (HP OmniBook Ultra 14)
- https://ratatoskr.run/linux-devicetree/2026/05/17018737/t (Glymur GPU DT)
- https://ratatoskr.run/linux-arm-msm/2026/09/17523924/t (TPM via QTEE)
- https://ratatoskr.run/linux-arm-msm/2026/09/17519558/t (cpufreq reporting)
- https://ratatoskr.run/linux-arm-msm/2026/06/17163323/t (eDP PHY v8 series)
- https://ratatoskr.run/lkml/2026/08/17386993/t (Zenbook HBR3-only report)
- https://github.com/bprendie/omarchy-snapdragon/issues/2
- https://github.com/FixItFoundry/zenbook-a16-linux
