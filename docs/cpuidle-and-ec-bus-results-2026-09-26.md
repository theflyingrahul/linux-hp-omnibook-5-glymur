# CPU Idle and EC Bus Results: September 26, 2026

This boot used the workstation GRUB entry with the BIOS-gated DSDT `_OSC`
override (`scripts/linux/glymur-dsdt-osc-fix.py`, BIOS F.06), on the stock
Ubuntu `7.0.0-30-generic` kernel with no DTB. Private logs are in
`.work/boot-osc-fix-20260926/` (full dmesg and journal) and
`.work/ec-gsi-live-20260926T205931Z/`.

## CPU idle: core states work; cluster states stay gated

- The kernel applied the override (`ACPI: Table Upgrade: override
  [DSDT-HPQOEM-8F47]`), and the platform `_OSC` completed with OS control
  mask `0x006e6efe`. The `AE_AML_BUFFER_LIMIT` abort is gone.
- `acpi_idle` registered with the `menu` governor and two per-core states
  from `_LPI`:
  - `NCC.C1`, latency 0;
  - `NCC.C4`, latency 500 µs.
  About six minutes after boot, CPU0 had spent 352 s in C4, which is core
  power collapse.
- Cluster states are not offered:
  - `\_SB.SYSM.CLS0._LPI` and `CLS1._LPI` return nothing unless `\_SB.PEPI`
    is set.
  - Only a `_DSM` (UUID `8d5ca34c-ae83-4a2a-9dd1-a74ffead548b`, function 1)
    sets it. Windows' PEP driver calls it when it takes over the platform's
    low-power resources, meaning RPMh sleep and wake votes on Qualcomm.
  - Linux has no such resource handling on the ACPI boot, so it does not set
    `PEPI`. Cluster and system idle belong to the device-tree path (RPMh and
    PSCI OS-initiated idle).
- The override remains a stopgap; see the script's header.

## EC bus (IC10) over GPI DMA: working

With `DMA_PRIVATE` set, `glymur_gpi_dma.ko` bound `QGP1` with no channel
taken at registration, even though `async_tx` was loaded. `glymur_geni_i2c_gsi.ko`
then bound IC10 as `i2c-3`: `CH START` completed for seid 1 with the I²C
protocol. In the previous boot it timed out for seid 0 with protocol 0.

The first EC read failed with `-ENOMEM`, before reaching the bus:

- Upstream maps GPI buffers against the SE's parent, which is the DT GENI
  wrapper. Under ACPI the parent is the platform root, so `dma_map_phys`
  warned about a missing DMA mask.
- The GSI derivation now maps against the device that performs the DMA, the
  GPI engine, whenever there is no wrapper.
- With that fix, `i2ctransfer -y 3 w1@0x76 0xb2 r1@0x76` returned `0x00`
  without errors, and the GPI interrupt count rose.

With the ACPI GenericSerialBus handler installed on IC10, firmware AML reaches
the EC:

- All four `acpitz` thermal zones now read real temperatures (40.8-42.8 °C
  at idle). Earlier boots read -200.
- Unbinding the first module ran IC10's `_REG` disconnect path. `SYKT` and
  `CSTS` issued about 40 EC transactions (registers `0xEF`, `0xE4`); all
  failed at DMA mapping in that module and did not reach the bus. Expect
  the same EC traffic on any future unbind.

## Still open

- Lid events need `_AEI` handling in `glymur_acpi_gpio.ko`.
- HP WMI needs `CONFIG_ACPI_WMI`, which the stock Ubuntu arm64 kernel lacks.
- Battery and AC still fail at `\_SB.ABD` (PMIC GLink).
- CPU frequency scaling: there is no `_CPC`.
- The failed services this boot are `pd-mapper` (Qualcomm protection-domain
  mapper, which expects DT remoteprocs) and `fwupd-refresh`.
