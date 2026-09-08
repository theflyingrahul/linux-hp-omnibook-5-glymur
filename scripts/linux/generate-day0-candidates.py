#!/usr/bin/env python3
import csv
import json
import os

def generate():
    hw_candidates = {}
    fw_candidates = {}
    
    with open('reference/hp-software/hardware-id-candidates.tsv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            hw_candidates[row['hardware_id']] = {
                'provider': row['provider'],
                'inf_source': row['inf_source'],
                'evidence': row['evidence']
            }
            
    with open('reference/hp-software/firmware-candidates.tsv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            fw_candidates[row['firmware_name']] = {
                'inf_source': row['inf_source'],
                'evidence': row['evidence']
            }
            
    out_dir = 'scripts/windows'
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'day0-candidates.json'), 'w', encoding='utf-8') as f:
        json.dump({
            'hardware_ids': hw_candidates,
            'firmware_names': fw_candidates
        }, f, indent=2, sort_keys=True)
        
if __name__ == '__main__':
    generate()
