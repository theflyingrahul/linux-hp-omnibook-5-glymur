#!/usr/bin/env python3
import os
import sys
import json
import csv
import hashlib
import argparse

def main():
    parser = argparse.ArgumentParser(description="Analyze Day-0 Hardware Capture")
    parser.add_argument('--capture', required=True, help="Path to capture directory")
    parser.add_argument('--allow-incomplete', action='store_true', help="Allow missing CAPTURE-COMPLETE.txt")
    parser.add_argument('--include-private-identity', action='store_true', help="Include private identity info in summary")
    args = parser.parse_args()

    capture_dir = args.capture
    complete_marker = os.path.join(capture_dir, 'CAPTURE-COMPLETE.txt')
    
    if not os.path.exists(complete_marker) and not args.allow_incomplete:
        print("ERROR: CAPTURE-COMPLETE.txt missing. Capture is incomplete. Use --allow-incomplete to override.")
        sys.exit(1)

    manifest_path = os.path.join(capture_dir, 'SHA256SUMS.tsv')
    if not os.path.exists(manifest_path):
        print("ERROR: SHA256SUMS.tsv missing.")
        sys.exit(1)
        
    print("Verifying capture hashes...")
    hash_errors = False
    with open(manifest_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        headers = next(reader, None)
        if headers and headers[0] == 'RelativePath':
            pass
        else:
            f.seek(0)
            
        for row in reader:
            if not row or row[0].startswith('#') or len(row) < 3: continue
            if headers and row[0] == 'RelativePath': continue
            rel_path, size, expected_hash = row[0], row[1], row[2]
            full_path = os.path.join(capture_dir, rel_path.replace('\\', '/'))
            
            if not os.path.exists(full_path):
                print(f"MISSING: {rel_path}")
                hash_errors = True
                continue
                
            hasher = hashlib.sha256()
            with open(full_path, 'rb') as tf:
                for chunk in iter(lambda: tf.read(4096), b""):
                    hasher.update(chunk)
            actual_hash = hasher.hexdigest().upper()
            if actual_hash != expected_hash.upper():
                print(f"HASH MISMATCH: {rel_path} (Expected {expected_hash}, Got {actual_hash})")
                hash_errors = True

    if hash_errors:
        print("ERROR: Hash validation failed.")
        sys.exit(1)
    else:
        print("PASS: All hashes validated.")

    candidates_path = 'scripts/windows/day0-candidates.json'
    hw_candidates = {}
    fw_candidates = {}
    if os.path.exists(candidates_path):
        with open(candidates_path, 'r', encoding='utf-8') as f:
            cdata = json.load(f)
            hw_candidates = cdata.get('hardware_ids', {})
            fw_candidates = cdata.get('firmware_names', {})

    os.makedirs('analysis', exist_ok=True)
    
    # Process PnP Data
    pnp_devices = []
    pnp_tsv = os.path.join(capture_dir, 'public', 'pnp', 'devices.tsv')
    if os.path.exists(pnp_tsv):
        with open(pnp_tsv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                pnp_devices.append(row.get('InstanceId', '').upper())

    # Process Firmware Data
    fw_observed = set()
    fw_tsv = os.path.join(capture_dir, 'raw', 'firmware', 'candidates.tsv')
    if os.path.exists(fw_tsv):
        with open(fw_tsv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                fw_observed.add(row.get('Filename', ''))

    def check_hw(hwid):
        for dev in pnp_devices:
            if hwid.upper() in dev:
                return True
        return False
        
    def check_fw(fwname):
        return fwname in fw_observed
        
    # Generate Summary
    with open('analysis/day0-summary.md', 'w', encoding='utf-8') as f:
        f.write("# Day-0 Evidence Summary\n\n")
        f.write("## Status\n")
        f.write("- Hashes: Validated\n\n")
        
        # WLAN Example Check
        c7700_hw = check_hw('PCI\\VEN_17CB&DEV_1107')
        c7700_fw = check_fw('wlanfw20.mbn')
        wlan_6900_hw = check_hw('PCI\\VEN_17CB&DEV_1112')
        wlan_6900_fw = check_fw('wlanfw.bin')
        
        f.write("## WLAN\n")
        f.write("### FastConnect C7700 / WCN785x\n")
        f.write(f"- Hardware: {'PCI\\VEN_17CB&DEV_1107 observed' if c7700_hw else 'Not observed'}\n")
        f.write(f"- Firmware: {'wlanfw20.mbn present' if c7700_fw else 'wlanfw20.mbn missing'}\n")
        if c7700_hw and c7700_fw:
            f.write("- Assessment: HARDWARE+SOFTWARE strongly corroborated\n")
        elif c7700_hw:
            f.write("- Assessment: HARDWARE-ONLY observed\n")
        elif c7700_fw:
            f.write("- Assessment: SOFTWARE-ONLY match; physical hardware UNKNOWN\n")
        else:
            f.write("- Assessment: NO-MATCH\n")
            
        f.write("### FastConnect 6900\n")
        f.write(f"- Hardware: {'PCI\\VEN_17CB&DEV_1112 observed' if wlan_6900_hw else 'Not observed'}\n")
        f.write(f"- Firmware: {'wlanfw.bin present' if wlan_6900_fw else 'wlanfw.bin missing'}\n")
        if wlan_6900_hw and wlan_6900_fw:
            f.write("- Assessment: HARDWARE+SOFTWARE strongly corroborated\n")
        elif wlan_6900_hw:
            f.write("- Assessment: HARDWARE-ONLY observed\n")
        elif wlan_6900_fw:
            f.write("- Assessment: SOFTWARE-ONLY match; physical hardware UNKNOWN\n")
        else:
            f.write("- Assessment: NO-MATCH\n")
            
        # Input Check
        elan_hw = check_hw('VID_04F3') or check_hw('VID_0A81')
        f.write("\n## Input\n")
        f.write("### ELAN Touchpad/Touchscreen\n")
        f.write(f"- Hardware: {'ELAN USB/I2C ID observed' if elan_hw else 'Not observed'}\n")
        f.write("- Assessment: " + ("HARDWARE-ONLY observed" if elan_hw else "NO-MATCH (or software-only)") + "\n")
        
        # Camera Check
        cam_hw = check_hw('VID_04F2&PID_B809') or check_hw('VID_30C9&PID_00D9')
        f.write("\n## Camera\n")
        f.write("### Huaqin Candidates\n")
        f.write(f"- Hardware: {'USB Camera ID observed' if cam_hw else 'Not observed'}\n")
        f.write("- Assessment: " + ("HARDWARE-ONLY observed" if cam_hw else "NO-MATCH (or software-only)") + "\n")
        
    with open('analysis/dts-evidence-gate.md', 'w', encoding='utf-8') as f:
        f.write("# DTS Evidence Gate\n\n")
        f.write("| Requirement | Status | Notes |\n")
        f.write("|---|---|---|\n")
        f.write(f"| WLAN Identity | {'SATISFIED' if c7700_hw or wlan_6900_hw else 'UNKNOWN'} | Based on PnP hardware enumeration |\n")
        f.write(f"| WLAN PCIe Root Path | UNKNOWN | Requires PnP location path / ACPI evidence |\n")
        f.write(f"| NVMe Host Path | UNKNOWN | Requires PnP location path / ACPI evidence |\n")
        
    print("Analysis generated in analysis/")

if __name__ == '__main__':
    main()
