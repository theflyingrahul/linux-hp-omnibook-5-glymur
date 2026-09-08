# Day-0 Execution Runbook

**DO NOT UPDATE THE BIOS OR WINDOWS BEFORE THIS RUNBOOK IS COMPLETE.**
The goal is to capture the pristine factory state as delivered.

### STEP 1: External & BIOS Photographic Capture
- Photograph the bottom service label (blur serials before sharing).
- Photograph left and right physical ports.
- Photograph the keyboard function row icons.
- Enter BIOS (F10 or Esc -> F10) and photograph:
  - System version / date
  - Secure Boot settings
  - Fast Boot / Boot Order
  - TPM / Security
  - USB / Display options
  - Charging options
  - Any Qualcomm-specific options

### STEP 2: Boot Factory Windows
- Complete the Windows Out-Of-Box Experience (OOBE).
- Do not connect to Wi-Fi if Windows allows it, to prevent background driver updates.
- If forced, let it complete, but do NOT manually trigger Windows Update.

### STEP 3: Transfer Scripts
- Copy the `linux-hp-omnibook-5-glymur` repository or the `scripts/windows` bundle onto a removable USB drive.

### STEP 4: First Metadata Capture (Pass 1)
- Open PowerShell (Elevated / Run as Administrator recommended).
- Execute:
  `.\day0-capture.ps1 -OutputPath E:\omnibook-day0`
- Wait for completion.
- Review output on a Linux host to ensure hashes and contents look sound.

### STEP 5: Second Preservation Capture (Pass 2)
- If approved, run a deeper extraction:
  `.\day0-capture.ps1 -OutputPath E:\omnibook-day0-full -ExportDrivers -CopyFirmware`
  (Optionally provide `-AcpiToolsPath` if you have `acpidump.exe`).
- This pass copies proprietary firmware and driver blobs. **DO NOT COMMIT THIS DIRECTORY.**

### STEP 6: Review & Preservation
- Complete Windows Recovery Media creation if desired.
- Back up your BitLocker Recovery Key to your Microsoft/HP account if active.
- Proceed to Linux experimentation only after you are satisfied with the captured evidence.
