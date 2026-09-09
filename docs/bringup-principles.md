# Bringup Principles

1. We construct a device tree for this machine.
2. We do not boot a DTB from another laptop.
3. Other Glymur DTS files may be consulted for:
   - bindings
   - SoC-level nodes
   - common Qualcomm architecture
   - driver examples
4. Machine-specific GPIOs, regulators, I2C devices, interrupts, clocks, firmware paths, addresses and similar properties must not be guessed.
5. Windows/ACPI/UEFI observations from the actual target will later be used as primary bring-up evidence.
6. Keep upstreamability in mind from the beginning.
7. Keep board-specific changes separate from generic Glymur kernel work where possible.
