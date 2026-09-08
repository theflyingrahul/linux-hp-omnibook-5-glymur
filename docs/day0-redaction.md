# Day-0 Redaction Guide

Before publishing any capture output, you MUST review the following for sensitive material:

1. **Serial Numbers and UUIDs**: Redact SMBIOS UUIDs, BIOS serials, and baseboard serials from public summaries. `private/identity/` isolates this data in the capture bundle.
2. **MAC Addresses**: Network MAC addresses may leak in PnP or Network outputs.
3. **Computer/User Names**: Check location paths, registry dumps, and driver logs for personal names.
4. **Bluetooth**: Enumerate devices carefully; paired device histories are not requested but may appear in raw logs.
5. **BitLocker**: Never publish protector IDs or recovery passwords. The capture script checks status only, but raw outputs must be reviewed.
