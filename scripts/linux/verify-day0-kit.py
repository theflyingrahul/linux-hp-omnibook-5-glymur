#!/usr/bin/env python3
import os
import sys
import hashlib
import csv

def main():
    if len(sys.argv) < 2:
        print("Usage: verify-day0-kit.py <path_to_kit_dir>")
        sys.exit(1)
        
    kit_dir = sys.argv[1]
    manifest_path = os.path.join(kit_dir, 'MANIFEST.tsv')
    
    if not os.path.exists(manifest_path):
        print(f"ERROR: {manifest_path} not found.")
        sys.exit(1)
        
    print(f"Verifying kit in {kit_dir}...")
    errors = False
    
    forbidden_exts = ['.exe', '.sys', '.dll', '.mbn', '.elf', '.bin', '.dtb', '.dts', '.dtsi']
    
    with open(manifest_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            rel_path = row['RelativePath']
            expected_hash = row['SHA256']
            full_path = os.path.join(kit_dir, rel_path)
            
            if not os.path.exists(full_path):
                print(f"MISSING: {rel_path}")
                errors = True
                continue
                
            _, ext = os.path.splitext(rel_path)
            if ext.lower() in forbidden_exts:
                print(f"FORBIDDEN EXTENSION: {rel_path}")
                errors = True
                
            hasher = hashlib.sha256()
            with open(full_path, 'rb') as tf:
                for chunk in iter(lambda: tf.read(4096), b""):
                    hasher.update(chunk)
            actual_hash = hasher.hexdigest().upper()
            
            if actual_hash != expected_hash.upper():
                print(f"HASH MISMATCH: {rel_path} (Expected {expected_hash}, Got {actual_hash})")
                errors = True

    for root, _, filenames in os.walk(kit_dir):
        for name in filenames:
            if name == 'MANIFEST.tsv': continue
            _, ext = os.path.splitext(name)
            if ext.lower() in forbidden_exts:
                print(f"FORBIDDEN EXTENSION FOUND ON DISK: {os.path.join(root, name)}")
                errors = True

    if errors:
        print("Kit verification FAILED.")
        sys.exit(1)
    else:
        print("Kit verification PASSED.")

if __name__ == '__main__':
    main()
