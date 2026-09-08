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

    # 1. Verify Hashes
    manifest_path = os.path.join(capture_dir, 'SHA256SUMS.tsv')
    if not os.path.exists(manifest_path):
        print("ERROR: SHA256SUMS.tsv missing.")
        sys.exit(1)
        
    print("Verifying capture hashes...")
    hash_errors = False
    with open(manifest_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        headers = next(reader, None)
        # Handle cases where CSV might not have headers or headers are different
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

    # 2. Load Candidates
    candidates_path = 'scripts/windows/day0-candidates.json'
    hw_candidates = {}
    fw_candidates = {}
    if os.path.exists(candidates_path):
        with open(candidates_path, 'r', encoding='utf-8') as f:
            cdata = json.load(f)
            hw_candidates = cdata.get('hardware_ids', {})
            fw_candidates = cdata.get('firmware_names', {})

    os.makedirs('analysis', exist_ok=True)

    # 3. Process Evidence
    observed_pnp = []
    pnp_json = os.path.join(capture_dir, 'raw', 'pnp', 'all-properties.json')
    if os.path.exists(pnp_json):
        with open(pnp_json, 'r', encoding='utf-8') as f:
            try:
                observed_pnp = json.load(f)
            except:
                pass

    hw_matches = []
    # Simplified matching logic for now
    # We will expand this in the actual summary report
    
    # 4. Generate Summary
    with open('analysis/day0-summary.md', 'w', encoding='utf-8') as f:
        f.write("# Day-0 Evidence Summary\n\n")
        f.write("## Status\n")
        f.write("- Hashes: Validated\n")
        
    with open('analysis/dts-evidence-gate.md', 'w', encoding='utf-8') as f:
        f.write("# DTS Evidence Gate\n\n")
        f.write("| Requirement | Status | Source |\n")
        f.write("|---|---|---|\n")
        f.write("| ACPI Tables | UNKNOWN | ACPIDUMP |\n")
        f.write("| WLAN Identity | UNKNOWN | PnP |\n")
        
    print("Analysis generated in analysis/")

if __name__ == '__main__':
    main()
