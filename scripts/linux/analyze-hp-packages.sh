#!/bin/bash
set -euo pipefail

EXTRACTED_DIR=".work/hp-software/extracted"

if [ ! -d "$EXTRACTED_DIR" ]; then
    echo "Directory $EXTRACTED_DIR not found. Please extract softpaqs first."
    exit 0
fi

echo "Inventorying extracted packages in $EXTRACTED_DIR ..."

find "$EXTRACTED_DIR" -type f -name "*.inf" | while read -r inf; do
    echo "----------------------------------------"
    echo "INF: $inf"
    ./scripts/linux/parse-windows-inf.py "$inf"
done
