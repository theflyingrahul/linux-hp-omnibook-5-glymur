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
        if not headers or headers[0] != 'RelativePath':
            # No header row or unexpected format, re-read from start
            f.seek(0)
            reader = csv.reader(f, delimiter='\t')

        for row in reader:
            if not row or row[0].startswith('#') or len(row) < 3: continue
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

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(os.path.dirname(script_dir))
    candidates_path = os.path.join(repo_root, 'scripts', 'windows', 'day0-candidates.json')
    hw_candidates = {}
    fw_candidates = {}
    if os.path.exists(candidates_path):
        with open(candidates_path, 'r', encoding='utf-8') as f:
            cdata = json.load(f)
            hw_candidates = cdata.get('hardware_ids', {})
            fw_candidates = cdata.get('firmware_names', {})

    analysis_dir = os.path.join(repo_root, 'analysis')
    os.makedirs(analysis_dir, exist_ok=True)
    
    # Process PnP Data
    pnp_devices = []
    pnp_tsv = os.path.join(capture_dir, 'public', 'pnp', 'devices.tsv')
    if os.path.exists(pnp_tsv):
        with open(pnp_tsv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                pnp_devices.append({
                    'instance_id': row.get('InstanceId', '').upper(),
                    'friendly_name': row.get('FriendlyName', '')
                })

    # The device table carries identity, while all-properties.json carries
    # Windows parent/location evidence needed to distinguish a PCI function
    # from its root port. Keep Linux DT node names unresolved until Linux-side
    # evidence exists.
    device_properties = {}
    properties_json = os.path.join(capture_dir, 'raw', 'pnp', 'all-properties.json')
    if os.path.exists(properties_json):
        with open(properties_json, 'r', encoding='utf-8') as f:
            for row in json.load(f):
                instance_id = row.get('InstanceId', '').upper()
                key_name = row.get('KeyName', '')
                if instance_id and key_name:
                    device_properties.setdefault(instance_id, {})[key_name] = row.get('Data', '')

    # Process Firmware Data
    fw_observed = set()
    fw_tsv = os.path.join(capture_dir, 'raw', 'firmware', 'candidates.tsv')
    if os.path.exists(fw_tsv):
        with open(fw_tsv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                # Capture filenames come from Windows, whose filesystem is
                # case-insensitive. Normalize before comparing with the
                # candidate database.
                fw_observed.add(row.get('Filename', '').casefold())

    def check_hw(hwid):
        for dev in pnp_devices:
            if hwid.upper() in dev['instance_id']:
                return True
        return False

    def friendly_matches(text):
        needle = text.casefold()
        return [
            dev for dev in pnp_devices
            if needle in dev['friendly_name'].casefold()
        ]

    names_by_instance = {
        dev['instance_id']: dev['friendly_name']
        for dev in pnp_devices
        if dev['instance_id']
    }

    def device_property(instance_id, key):
        return device_properties.get(instance_id.upper(), {}).get(key, '')

    def windows_topology(dev):
        if not dev:
            return 'Not observed'

        parts = []
        current = dev['instance_id']
        visited = set()
        for level in range(4):
            if not current or current in visited:
                break
            visited.add(current)
            name = names_by_instance.get(current, '')
            if current.startswith('ACPI\\PNP0A08') and name:
                name = f'{name} ({current})'
            location = device_property(current, 'DEVPKEY_Device_LocationInfo')
            if name and location:
                parts.append(f'{name}: {location}')
            elif location:
                parts.append(location)
            elif name:
                parts.append(name)
            else:
                parts.append(current)
            if current.startswith('ACPI\\PNP0A08'):
                break
            current = device_property(current, 'DEVPKEY_Device_Parent')

        return '; '.join(parts)
        
    def check_fw(fwname):
        return fwname.casefold() in fw_observed
        
    # Generate Summary
    with open(os.path.join(analysis_dir, 'day0-summary.md'), 'w', encoding='utf-8') as f:
        f.write("# Day-0 Evidence Summary\n\n")
        f.write("## Status\n")
        f.write("- Hashes: Validated\n\n")
        
        # WLAN identity is taken from the Windows FriendlyName when present.
        # Device IDs alone are not sufficient: DEV_1112 is reported as C7700
        # on the target capture, so do not hard-code a model-to-ID mapping.
        c7700_devices = friendly_matches('FastConnect C7700')
        c7700_hw = bool(c7700_devices)
        c7700_fw = check_fw('wlanfw20.mbn')
        alternate_wlan_devices = friendly_matches('FastConnect 6900')
        alternate_wlan_hw = bool(alternate_wlan_devices)
        alternate_wlan_fw = check_fw('wlanfw.bin')
        nvme_devices = [
            dev for dev in pnp_devices
            if 'SCSI\\DISK&VEN_NVME' in dev['instance_id']
            or 'NVME' in dev['friendly_name'].upper()
        ]
        wlan_topology = windows_topology(c7700_devices[0] if c7700_devices else None)
        nvme_topology = windows_topology(nvme_devices[0] if nvme_devices else None)
        
        f.write("## WLAN\n")
        f.write("### FastConnect C7700\n")
        c7700_label = c7700_devices[0]['friendly_name'] if c7700_devices else 'Not observed'
        f.write(f"- Hardware: {c7700_label}\n")
        f.write(f"- Firmware: {'wlanfw20.mbn present' if c7700_fw else 'wlanfw20.mbn missing'}\n")
        if c7700_hw and c7700_fw:
            f.write("- Assessment: HARDWARE+SOFTWARE strongly corroborated\n")
        elif c7700_hw:
            f.write("- Assessment: HARDWARE-ONLY observed\n")
        elif c7700_fw:
            f.write("- Assessment: SOFTWARE-ONLY match; physical hardware UNKNOWN\n")
        else:
            f.write("- Assessment: NO-MATCH\n")
            
        f.write("### Alternate WLAN candidate (FastConnect 6900 mapping unconfirmed)\n")
        alternate_wlan_label = alternate_wlan_devices[0]['friendly_name'] if alternate_wlan_devices else 'Not observed'
        f.write(f"- Hardware: {alternate_wlan_label}\n")
        f.write(f"- Firmware: {'wlanfw.bin present' if alternate_wlan_fw else 'wlanfw.bin missing'}\n")
        if alternate_wlan_hw and alternate_wlan_fw:
            f.write("- Assessment: HARDWARE+SOFTWARE candidate match\n")
        elif alternate_wlan_hw:
            f.write("- Assessment: HARDWARE-ONLY observed\n")
        elif alternate_wlan_fw:
            f.write("- Assessment: SOFTWARE-ONLY candidate; component identity UNKNOWN\n")
        else:
            f.write("- Assessment: NO-MATCH\n")
            
        # Input Check
        elan_hw = (
            check_hw('HID\\VEN_ELAN') or
            check_hw('HID\\ELAN') or
            check_hw('ACPI\\ELAN')
        )
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

        f.write("\n## Windows PCIe Topology Evidence\n")
        f.write(f"- WLAN: {wlan_topology}\n")
        f.write(f"- NVMe: {nvme_topology}\n")
        f.write("- Linux PCIe controller/node mapping: not assessed by this Windows capture analyzer; see docs/linux-node-mapping-2026-09-14.md\n")
        
        # Generic candidate scan
        # NOTE: The above hardcoded WLAN/Input/Camera sections check specific IDs.
        # This generic section iterates all candidates from day0-candidates.json.
        if hw_candidates:
            f.write("\n## All Candidate Matches\n")
            f.write("| Hardware ID | PnP Match | Category |\n")
            f.write("|---|---|---|\n")
            for hwid, info in sorted(hw_candidates.items()):
                matched = check_hw(hwid)
                status = "OBSERVED" if matched else "NOT OBSERVED"
                f.write(f"| {hwid} | {status} | {info.get('evidence', 'HP-SOFTWARE')} |\n")

        if fw_candidates:
            f.write("\n## All Firmware Matches\n")
            f.write("| Firmware | Present | Category |\n")
            f.write("|---|---|---|\n")
            for fwname, info in sorted(fw_candidates.items()):
                present = check_fw(fwname)
                status = "PRESENT" if present else "ABSENT"
                f.write(f"| {fwname} | {status} | {info.get('evidence', 'HP-SOFTWARE')} |\n")
        
    with open(os.path.join(analysis_dir, 'dts-evidence-gate.md'), 'w', encoding='utf-8') as f:
        f.write("# Target Hardware Evidence Gate\n\n")
        f.write("| Requirement | Status | Notes |\n")
        f.write("|---|---|---|\n")
        f.write(f"| WLAN Identity | {'SATISFIED' if c7700_hw or alternate_wlan_hw else 'UNKNOWN'} | Based on PnP hardware enumeration |\n")
        f.write(f"| WLAN Windows PCIe path | {'WINDOWS-OBSERVED' if c7700_devices else 'UNKNOWN'} | {wlan_topology}; Linux node mapping not assessed here |\n")
        f.write(f"| NVMe Windows PCIe path | {'WINDOWS-OBSERVED' if nvme_devices else 'UNKNOWN'} | {nvme_topology}; Linux node mapping not assessed here |\n")
        
    print("Analysis generated in analysis/")

if __name__ == '__main__':
    main()
