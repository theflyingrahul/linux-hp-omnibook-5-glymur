#!/usr/bin/env python3
import os
import shutil
import hashlib
import csv
import zipfile
import subprocess

def get_git_commit():
    try:
        return subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD']).decode('utf-8').strip()
    except:
        return "unknown"

def main():
    commit = get_git_commit()
    version = "0.1.1"
    
    release_dir = ".work/releases"
    os.makedirs(release_dir, exist_ok=True)
    
    kit_name = f"omnibook5-day0-kit-{version}-{commit}"
    kit_dir = os.path.join(release_dir, kit_name)
    
    if os.path.exists(kit_dir):
        shutil.rmtree(kit_dir)
    os.makedirs(kit_dir)
    
    # Files to include
    files = [
        ('scripts/windows/day0-capture.ps1', 'day0-capture.ps1'),
        ('scripts/windows/helpers.ps1', 'helpers.ps1'),
        ('scripts/windows/test-day0-static.ps1', 'test-day0-static.ps1'),
        ('scripts/windows/day0-candidates.json', 'day0-candidates.json')
    ]
    
    # Readme
    with open(os.path.join(kit_dir, 'README.txt'), 'w', encoding='utf-8') as f:
        f.write("Day-0 Hardware Capture Kit\n")
        f.write("--------------------------\n")
        f.write("1. DO NOT run Windows Update / HP updates intentionally before first capture if practical.\n")
        f.write("2. Open Windows PowerShell.\n")
        f.write("3. First run:\n")
        f.write("       .\\day0-capture.ps1 -Preflight -OutputPath <external-path>\n")
        f.write("4. Review result.\n")
        f.write("5. Then run metadata capture:\n")
        f.write("       .\\day0-capture.ps1 -OutputPath <external-path>\n")
        f.write("6. Do not use -ExportDrivers or -CopyFirmware on the first pass unless already decided.\n")
        f.write("7. The script does not modify BIOS, partitions, drivers, BitLocker, or Secure Boot.\n")
    
    # Copy and Hash
    manifest_data = []
    for src, dst in files:
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(kit_dir, dst))
            
    for root, _, filenames in os.walk(kit_dir):
        for name in filenames:
            if name == 'MANIFEST.tsv': continue
            filepath = os.path.join(root, name)
            relpath = os.path.relpath(filepath, kit_dir)
            size = os.path.getsize(filepath)
            
            hasher = hashlib.sha256()
            with open(filepath, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hasher.update(chunk)
            filehash = hasher.hexdigest().upper()
            manifest_data.append(f"{relpath}\t{size}\t{filehash}")
            
    with open(os.path.join(kit_dir, 'MANIFEST.tsv'), 'w', encoding='utf-8') as f:
        f.write("RelativePath\tSize\tSHA256\n")
        for line in sorted(manifest_data):
            f.write(line + "\n")
            
    # Create ZIP deterministically if possible (for now standard zip)
    zip_path = os.path.join(release_dir, f"{kit_name}.zip")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, _, filenames in os.walk(kit_dir):
            for name in filenames:
                filepath = os.path.join(root, name)
                arcname = os.path.relpath(filepath, release_dir)
                zf.write(filepath, arcname)
                
    print(f"Kit generated at {zip_path}")
    
    hasher = hashlib.sha256()
    with open(zip_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    zip_hash = hasher.hexdigest().upper()
    print(f"ZIP SHA256: {zip_hash}")

if __name__ == '__main__':
    main()
