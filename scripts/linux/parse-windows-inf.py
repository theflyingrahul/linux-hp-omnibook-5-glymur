#!/usr/bin/env python3
import sys
import os
import re

def parse_inf(inf_path):
    try:
        with open(inf_path, 'r', encoding='utf-16') as f:
            lines = f.read().splitlines()
    except Exception:
        try:
            with open(inf_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.read().splitlines()
        except Exception:
            return {}

    # Strip comments and empty lines
    cleaned_lines = []
    for line in lines:
        line = line.split(';', 1)[0].strip()
        if line:
            cleaned_lines.append(line)

    strings = {}
    current_section = None
    sections = {}

    # Basic section parsing
    for line in cleaned_lines:
        match = re.match(r'\[([^\]]+)\]', line)
        if match:
            current_section = match.group(1).lower()
            if current_section not in sections:
                sections[current_section] = []
        elif current_section:
            sections[current_section].append(line)

    # Parse strings section
    if 'strings' in sections:
        for line in sections['strings']:
            if '=' in line:
                key, val = line.split('=', 1)
                strings[key.strip().lower()] = val.strip(' "\'')

    def resolve_string(val):
        if not val: return val
        # resolve %StringToken%
        def repl(m):
            token = m.group(1).lower()
            return strings.get(token, m.group(0))
        return re.sub(r'%([^%]+)%', repl, val)

    provider = ""
    class_name = ""
    class_guid = ""
    driver_ver = ""
    catalog_file = ""
    hw_ids = set()
    services = set()
    firmware_refs = set()

    if 'version' in sections:
        for line in sections['version']:
            if '=' not in line: continue
            k, v = [x.strip() for x in line.split('=', 1)]
            k_lower = k.lower()
            v_res = resolve_string(v.strip(' "\''))
            if k_lower == 'provider': provider = v_res
            if k_lower == 'class': class_name = v_res
            if k_lower == 'classguid': class_guid = v_res
            if k_lower == 'driverver': driver_ver = v_res
            if k_lower == 'catalogfile': catalog_file = v_res

    # Hardware IDs (from Manufacturer and specific model sections)
    models_sections = []
    if 'manufacturer' in sections:
        for line in sections['manufacturer']:
            if '=' in line:
                val = line.split('=', 1)[1]
                # Format: %MfgName% = ModelSection, NTarm64...
                parts = [x.strip() for x in val.split(',')]
                if len(parts) > 0:
                    models_sections.append(parts[0].lower())
                if len(parts) > 1:
                    for arch in parts[1:]:
                        models_sections.append(f"{parts[0]}.{arch}".lower())

    for sec in models_sections:
        if sec in sections:
            for line in sections[sec]:
                if '=' in line:
                    val = line.split('=', 1)[1]
                    hwid_parts = [x.strip() for x in val.split(',')]
                    if len(hwid_parts) > 1:
                        # hwid is usually the second part and onwards
                        for h in hwid_parts[1:]:
                            hw_ids.add(h)

    # General regex fallback for IDs across the file
    for line in cleaned_lines:
        if re.search(r'(ACPI|PCI|USB|HID|I2C|VMBUS)\\[a-zA-Z0-9_&]+', line, re.IGNORECASE):
            matches = re.findall(r'(ACPI\\[a-zA-Z0-9_&]+|PCI\\[a-zA-Z0-9_&]+|USB\\[a-zA-Z0-9_&]+|HID\\[a-zA-Z0-9_&]+|I2C\\[a-zA-Z0-9_&]+)', line, re.IGNORECASE)
            for m in matches:
                hw_ids.add(m)

        # Services
        if 'addservice' in line.lower() and '=' in line:
            parts = line.split('=')[1].split(',')
            if len(parts) > 0:
                services.add(resolve_string(parts[0].strip()))

        # Firmware/Files
        # High confidence firmware
        if re.search(r'\.(mbn|elf|melf|fw|bdf|tlv|jsn|json|cfg|bin)', line, re.IGNORECASE):
            matches = re.findall(r'[a-zA-Z0-9_.\-]+\.(?:mbn|elf|melf|fw|bdf|tlv|jsn|json|cfg|bin)', line, re.IGNORECASE)
            for m in matches:
                firmware_refs.add(m)

    return {
        "provider": provider,
        "class": class_name,
        "class_guid": class_guid,
        "driver_ver": driver_ver,
        "catalog_file": catalog_file,
        "hw_ids": sorted(list(hw_ids)),
        "services": sorted(list(services)),
        "firmware_refs": sorted(list(firmware_refs))
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
