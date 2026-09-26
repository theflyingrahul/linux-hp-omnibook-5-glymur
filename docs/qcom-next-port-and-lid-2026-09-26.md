# Lid Events and the qcom-next Kernel Port: September 26, 2026

## Lid events work (live, stock Ubuntu 7.0)

- `glymur_acpi_ged.ko`, built from `derive-evged.py --module`, bound `LIGE`
  (`ACPI0013:01`) on GPIO 92 (PDC pin 960), both edges.
- Closing and opening the lid fired the GED interrupt and ran `_EVT`, which
  read the EC over IC10/GPI DMA. `/proc/acpi/button/lid/LID0` switched
  closed/open, and `systemd-logind` logged "Lid closed." and "Lid opened."
  There were no kernel errors. Logs: `.work/lid-ged-watch-20260926.log`
  (private).
- `ECGE` (EC events, `ACPI0013:00`, PDC pin 768 -> GPIO 66) was refused
  because the GPIO module's `pins` list lacked 66. The staged desktop setup
  now passes `pins=3,51,66,67,92` and loads `glymur_acpi_ged.ko` after the
  EC bus; this is untested until the next boot.
- The upstream form is `patches/kernel/0006-ACPI-GED-Support-GpioInt-event-resources.patch`.
  It applies to mainline, where `evged.c` is unchanged since v7.0.

## Moving to the qcom-next kernel (in progress)

The owner decided to run Qualcomm's qcom-next (7.3.0-rc2, `a47c4c5aa`)
instead of Ubuntu's 7.0. Most missing drivers are there: `pmic_glink` and
`battmgr`, ADSP PAS, `cpufreq-hw`, MSM GPU and display, and UCSI.

Done:

- The config is Ubuntu's `config-7.0.0-30-generic` plus
  `arch/arm64/configs/qcom.config`, with `DEBUG_INFO_NONE`, empty
  trusted/revocation keys, no forced module signing, and
  `LOCALVERSION=-glymur`. All the Qualcomm drivers above end up enabled.
  Secure Boot is disabled on this laptop, so a self-built kernel boots.
- `0006` applies cleanly to qcom-next.
- `0007-glymur-acpi-gpi-and-geni-i2c-wip.diff` (against `a47c4c5aa`,
  `patch -p1`) ports the proven module logic into the real drivers:
  - `gpi.c`: an ACPI match for `QCOM0F88` with Glymur window and EE-offset
    match data, the GPII count from the ACPI interrupt count, and an exported
    `gpi_acpi_request_chan()`. qcom-next already sets `DMA_PRIVATE`.
  - `i2c-qcom-geni.c`: a firmware-owned `QCOM0F10` descriptor. It uses
    `CLKD` timing, the bus speed from the ACPI children, a firmware-state
    gate, wrapper-free FIFO depth, a GPI engine found through `_DEP`, the
    SE index from the MMIO base, and GPI buffers mapped against the engine.
  - Kconfig: `I2C_QCOM_GENI` depends on `QCOM_GPI_DMA || !QCOM_GPI_DMA`.
- `0008-glymur_acpi_gpio-intree-wip.c` is the GPIO/PDC driver to add as
  `drivers/gpio/glymur_acpi_gpio.c` (Kconfig/Makefile entry still to write),
  with default pins `3,51,66,67,92`.

Not done: none of this has been compiled yet, no kernel is installed, and
there is no GRUB entry.

## Blocker hit: the installer USB cannot take a kernel tree

Checking the 2.1 GB qcom-next tree out into the USB's `casper-rw`
persistence (ext3, `data=ordered`) left about 1.3 GB dirty. The stick
drained it at about 1.7 MB/s, and every metadata operation on the
filesystem, including `ls` and `git`, blocked behind it for many minutes.
Kernel sources and builds must live in RAM (`tmpfs`, about 26 GB free);
only the finished kernel and modules (a few hundred MB) should reach the
USB. The `.work/linux-qcom-next` checkout on the USB should be deleted once
the filesystem responds.

## Next steps

1. Fetch qcom-next into tmpfs, apply 0006 and 0007, add 0008 with a Kconfig
   entry, and build with the config above.
2. Install the modules into the persistent root, build a casper-capable
   initrd, copy the `Image` to the FAT partition, and add a separate GRUB
   entry. Keep the current entries.
3. First boot: ACPI, no DTB, same kit behaviour, to prove the kernel.
4. Then the HP DTS. The ADSP/CDSP/GPU firmware (`qcadsp8480.mbn`,
   `adsp_dtbs.elf`, `qccdsp8480.mbn`, `cdsp_dtbs.elf`,
   `qcdxkmsuc8480.mbn`, `adsp*.jsn`) is not in `.work/`. It has to come
   from HP's Qualcomm Driver Pack for the 16-bf1000 or from the Windows
   driver store (`qcsubsys_ext_adsp8480.inf_*`, `qcnspmcdm8480.inf_*`,
   `qcdx8480.inf_*`). HP's reference catalogue has no `8F47` entry and the
   support page refuses scripted access.
