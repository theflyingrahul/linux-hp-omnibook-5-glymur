#!/usr/bin/env python3
import sys
import os
import re
import configparser

def parse_inf(inf_path):
    try:
        with open(inf_path, 'r', encoding='utf-16') as f:
            content = f.read()
    except:
        try:
            with open(inf_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except:
            return {}
            
    # Simple regex-based extraction of hardware IDs and services
    # because configparser is strict about INF format quirks
    provider = ""
    class_name = ""
    class_guid = ""
    driver_ver = ""
    catalog_file = ""
    hw_ids = set()
    services = set()
    firmware_refs = set()
    
    for line in content.splitlines():
        line = line.strip()
        if line.startswith(';'): continue
        if line.lower().startswith('provider='): provider = line.split('=', 1)[1].strip(' "\'')
        if line.lower().startswith('class='): class_name = line.split('=', 1)[1].strip(' "\'')
        if line.lower().startswith('classguid='): class_guid = line.split('=', 1)[1].strip(' "\'')
        if line.lower().startswith('driverver='): driver_ver = line.split('=', 1)[1].strip(' "\'')
        if line.lower().startswith('catalogfile='): catalog_file = line.split('=', 1)[1].strip(' "\'')
        if 'service' in line.lower() and 'addservice' in line.lower():
            # Example: AddService = %ServiceName%, 0x00000002, Service_Inst
            parts = line.split(',')
            if len(parts) > 0:
                svc = parts[0].split('=')[-1].strip()
                services.add(svc)
        
        # Hardware IDs often look like: %DeviceDesc% = InstallSection, ACPI\VEN_QCOM&DEV_0123
        # Or PCI\VEN_xxxx&DEV_yyyy
        if re.search(r'(ACPI|PCI|USB|HID|I2C)\\[a-zA-Z0-9_&]+', line, re.IGNORECASE):
            matches = re.findall(r'(ACPI\\[a-zA-Z0-9_&]+|PCI\\[a-zA-Z0-9_&]+|USB\\[a-zA-Z0-9_&]+|HID\\[a-zA-Z0-9_&]+|I2C\\[a-zA-Z0-9_&]+)', line, re.IGNORECASE)
            for m in matches:
                hw_ids.add(m)
        
        # Firmware references usually have .mbn, .bin, .elf
        if re.search(r'\.(mbn|bin|elf|fw|bdf|tlv|dat|jsn|json|cfg)', line, re.IGNORECASE):
            matches = re.findall(r'[a-zA-Z0-9_.\-]+\.(?:mbn|bin|elf|fw|bdf|tlv|dat|jsn|json|cfg)', line, re.IGNORECASE)
            for m in matches:
                firmware_refs.add(m)

    return {
        "provider": provider,
        "class": class_name,
        "class_guid": class_guid,
        "driver_ver": driver_ver,
        "catalog_file": catalog_file,
        "hw_ids": list(hw_ids),
        "services": list(services),
        "firmware_refs": list(firmware_refs)
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: parse-windows-inf.py <file.inf>")
        sys.exit(1)
    res = parse_inf(sys.argv[1])
    for k, v in res.items():
        if isinstance(v, list):
            print(f"{k}: {', '.join(v)}")
        else:
            print(f"{k}: {v}")
