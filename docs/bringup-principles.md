# Bringup Principles

1. Keep the UEFI/ACPI boot path available while evaluating a target-specific device tree. Choose the path from measured driver support, not from the existence of a reference DTB.
2. We do not boot a DTB from another laptop.
3. Other Glymur DTS files may be consulted for:
   - bindings
   - SoC-level nodes
   - common Qualcomm architecture
   - driver examples
4. Machine-specific GPIOs, regulators, I2C devices, interrupts, clocks, firmware paths, addresses and similar properties must not be guessed.
5. Windows/ACPI/UEFI observations from the actual target are primary bring-up evidence; the elevated metadata capture, ACPICA binary-table capture, and combined decompilation are recorded separately from the pending topology review.
6. Keep upstreamability in mind from the beginning.
7. Keep board-specific changes separate from generic Glymur kernel work where possible.
