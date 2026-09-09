#!/usr/bin/env python3
import sys
import re

def promote(manifest_file):
    hwids = set()
    firmware = set()
    
    with open(manifest_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    blocks = content.split('----------------------------------------')
    for block in blocks:
        if not block.strip(): continue
        lines = block.strip().splitlines()
        inf_path = lines[0].strip(' -')
        provider = ""
        hw_line = ""
        fw_line = ""
        for line in lines[1:]:
            if line.startswith('provider: '): provider = line.split(': ', 1)[1]
            if line.startswith('hw_ids: '): hw_line = line.split(': ', 1)[1]
            if line.startswith('firmware_refs: '): fw_line = line.split(': ', 1)[1]
            
        if hw_line:
            for hw in hw_line.split(', '):
                if hw: hwids.add((hw, provider, inf_path.split('/')[-1]))
        if fw_line:
            for fw in fw_line.split(', '):
                if fw: firmware.add((fw, inf_path.split('/')[-1]))
                
    # Update TSVs
    print("Promoting Hardware IDs...")
    # NOTE: This overwrites the existing file each time
    with open('reference/hp-software/hardware-id-candidates.tsv', 'w', encoding='utf-8') as f:
        f.write("hardware_id\tprovider\tinf_source\tevidence\n")
        for hw, prov, inf in sorted(list(hwids)):
            f.write(f"{hw}\t{prov}\t{inf}\tHP-SOFTWARE\n")
            
    print("Promoting Firmware Candidates...")
    # NOTE: This overwrites the existing file each time
    with open('reference/hp-software/firmware-candidates.tsv', 'w', encoding='utf-8') as f:
        f.write("firmware_name\tinf_source\tevidence\n")
        for fw, inf in sorted(list(firmware)):
            f.write(f"{fw}\t{inf}\tHP-SOFTWARE\n")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: promote-hp-analysis.py <manifest-file>')
        sys.exit(1)
    promote(sys.argv[1])
