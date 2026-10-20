# Video: Iris Decoder and Encoder, October 20, 2026

Issue #9. Read-only work on the driver pack and the kernel trees; the test
runs on the next boot.

## What Linux already has

qcom-next `1a0586064ee1` supports Iris on Glymur: `388ad6322cd3`
(FROMLIST, "media: iris: Add platform data for glymur") and
`iris: video-codec@aa00000` (`qcom,glymur-iris`, disabled) in
`glymur.dtsi`. The Glymur CRD enables it with
`firmware-name = "qcom/vpu/vpu36_p4_s7.mbn"` and a `video-firmware`
subnode (`iommus = <&apps_smmu 0x19e2 0x0>`); the Mahua CRD includes
`glymur-crd.dtsi`, so Qualcomm runs the same node on Mahua, and
`mahua.dtsi` leaves the node alone. Our kernel builds
`CONFIG_VIDEO_QCOM_IRIS=m` and `CONFIG_CLK_GLYMUR_VIDEOCC=m` (videocc
already probes on our boots).

## The firmware

Windows loads the video firmware from the display driver package
(`qcdx8480`): `qcvss8480.mbn`, committed unmodified under
`boards/hp-omnibook-5-16-bf1xxx/firmware/qcdx8480/`.

| | HP `qcvss8480.mbn` | linux-firmware `qcom/vpu/vpu36_p4_s7.mbn` |
|---|---|---|
| Version | `video-firmware.3.6-aeb98f00…` | `vfw-3.6:rel0049-1bebe930…` |
| ELF machine, segments | 94, 22 | 94, 22 |
| Load layout | identical | identical |
| Signing | HP production (`IMAGE_VARIANT_STRING=PROD`) | Qualcomm |

Same generation and layout; the difference is the signature. As with the
ADSP and CDSP, a laptop has to load the image signed for it, which is why
upstream laptop device trees point Iris (or Venus) at Windows' `qcvss`
image under a vendor directory: `qcom/sc8280xp/LENOVO/21BX/qcvss8280.mbn`
(ThinkPad X13s), `qcom/x1e80100/LENOVO/91B6/qcvss8380.mbn` (IdeaCentre
Mini). No Glymur laptop enables Iris upstream yet. (`qcav1e8480.mbn` in the
same package is a separate AV1 encoder image; upstream Iris does not use
it.)

## The test (kernel -15, test device tree)

- `&iris` as on the CRD, with
  `firmware-name = "qcom/glymur/HP/omnibook-5-16-bf1xxx/qcvss8480.mbn"`,
  next to HP's ADSP and CDSP images.
- `install-from-usb.sh` installs the image from the USB kit (`hp-fw/`);
  `install-firmware.sh` does the same from a checkout.
- `check-video.sh` lists the V4L2 devices and decodes a generated 1080p
  H.264 clip with `h264_v4l2m2m` and in software, with the CPU time each
  took.

If the firmware is refused (a PAS authentication error in the log) or the
driver probe fails, the daily device tree is unaffected: only the test
tree enables the node.
