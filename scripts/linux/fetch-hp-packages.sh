#!/bin/bash
set -euo pipefail

MANIFEST="reference/hp-software/d3zn3ua-packages.tsv"
DOWNLOAD_DIR=".work/hp-software/downloads"

list_packages() {
    if [ ! -f "$MANIFEST" ]; then
        echo "Error: Manifest $MANIFEST not found."
        exit 1
    fi
    echo "Packages in manifest:"
    awk -F'\t' 'NR>1 {print $2 " - " $3 " (" $8 ")"}' "$MANIFEST"
}

download_package() {
    local softpaq="$1"
    if [ ! -f "$MANIFEST" ]; then
        echo "Error: Manifest $MANIFEST not found."
        exit 1
    fi
    
    local line
    line=$(awk -F'\t' -v sp="$softpaq" '$2 == sp {print $0}' "$MANIFEST")
    if [ -z "$line" ]; then
        echo "Error: SoftPaq $softpaq not found in manifest."
        exit 1
    fi
    
    local url
    url=$(echo "$line" | cut -f7)
    local expected_hash
    expected_hash=$(echo "$line" | cut -f6)
    local filename
    filename=$(basename "$url")
    
    echo "Downloading $softpaq from $url ..."
    mkdir -p "$DOWNLOAD_DIR"
    local target="$DOWNLOAD_DIR/$filename"
    
    # Simple curl since direct SoftPaq URLs (ftp.hp.com / hp.com) are usually not Akamai blocked for the files themselves
    curl -L -C - -o "$target" "$url"
    
    if grep -iq "<html" "$target"; then
        echo "Error: Downloaded file appears to be HTML (possible block/redirect)."
        rm -f "$target"
        exit 1
    fi
    
    if [ -n "$expected_hash" ] && [ "$expected_hash" != "TBD" ]; then
        local actual_hash
        actual_hash=$(sha256sum "$target" | awk '{print $1}')
        if [ "$actual_hash" != "$expected_hash" ]; then
            echo "Error: Hash mismatch for $filename"
            echo "Expected: $expected_hash"
            echo "Actual:   $actual_hash"
            exit 1
        fi
        echo "Hash OK."
    fi
    echo "Downloaded: $target"
}

case "${1:-}" in
    --list)
        list_packages
        ;;
    --download)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 --download <softpaq>"
            exit 1
        fi
        download_package "$2"
        ;;
    --download-all)
        awk -F'\t' 'NR>1 {print $2}' "$MANIFEST" | while read -r sp; do
            download_package "$sp"
        done
        ;;
    *)
        echo "Usage: $0 [--list | --download <softpaq> | --download-all]"
        exit 1
        ;;
esac
