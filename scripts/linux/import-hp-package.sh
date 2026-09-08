#!/usr/bin/env bash
set -e

LOCAL_FILE=""
SOFTPAQ="UNKNOWN"
TITLE="UNKNOWN"
SCOPE="UNKNOWN"

usage() {
    echo "Usage: $0 --local <file> [--softpaq spNNNNNN] [--title \"Title\"] [--scope EXACT-SKU|FAMILY|UNKNOWN]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --local) LOCAL_FILE="$2"; shift ;;
        --softpaq) SOFTPAQ="$2"; shift ;;
        --title) TITLE="$2"; shift ;;
        --scope) SCOPE="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "$LOCAL_FILE" || ! -e "$LOCAL_FILE" ]]; then
    echo "Error: Local file missing."
    exit 1
fi

if [[ -d "$LOCAL_FILE" ]]; then
    echo "Error: Local file is a directory."
    exit 1
fi

if [[ ! -s "$LOCAL_FILE" ]]; then
    echo "Error: Local file is zero bytes."
    exit 1
fi

# Detect obvious HTML/error pages
head -c 256 "$LOCAL_FILE" | grep -qi -E "<!DOCTYPE html|<html|Access Denied|Akamai" && { echo "Error: File appears to be an HTML or blocked page."; exit 1; }

# Calculate info
FILE_SIZE=$(stat -c%s "$LOCAL_FILE")
FILE_SHA256=$(sha256sum "$LOCAL_FILE" | awk '{print $1}')
FILE_TYPE=$(file -b "$LOCAL_FILE")
BASE_NAME=$(basename "$LOCAL_FILE")

# Safe package ID
SHORT_SHA=${FILE_SHA256:0:8}
SAFE_NAME=$(echo "$BASE_NAME" | tr -dc 'a-zA-Z0-9.-')
PKG_ID="${SAFE_NAME}-${SHORT_SHA}"

# Paths
DOWNLOAD_DIR=".work/hp-software/downloads"
EXTRACT_DIR=".work/hp-software/extracted/${PKG_ID}"
MANIFEST_DIR=".work/hp-software/manifests"
mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR" "$MANIFEST_DIR"

DEST_FILE="${DOWNLOAD_DIR}/${SAFE_NAME}"
if [[ ! -f "$DEST_FILE" ]]; then
    cp "$LOCAL_FILE" "$DEST_FILE"
fi

echo "Importing $DEST_FILE ($FILE_SIZE bytes, SHA256: $FILE_SHA256)"

# Static Extraction
echo "Attempting static extraction..."
EXTRACTED=0

if command -v 7z >/dev/null 2>&1; then
    7z x "$DEST_FILE" -o"${EXTRACT_DIR}" -y >/dev/null 2>&1 && EXTRACTED=1
elif command -v cabextract >/dev/null 2>&1; then
    cabextract -d "${EXTRACT_DIR}" "$DEST_FILE" >/dev/null 2>&1 && EXTRACTED=1
elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$DEST_FILE" -C "${EXTRACT_DIR}" >/dev/null 2>&1 && EXTRACTED=1
elif command -v unzip >/dev/null 2>&1; then
    unzip -q "$DEST_FILE" -d "${EXTRACT_DIR}" >/dev/null 2>&1 && EXTRACTED=1
fi

if [[ $EXTRACTED -eq 0 ]]; then
    echo "EXTRACTION BLOCKED: No suitable extraction utility found or extraction failed."
    echo "Try installing 7z, cabextract, bsdtar, or unzip."
    exit 1
fi

echo "Extraction successful."

# Run analysis tools
MANIFEST_FILE="${MANIFEST_DIR}/${PKG_ID}-manifest.json"
echo "{" > "$MANIFEST_FILE"
echo "  \"package_id\": \"$PKG_ID\"," >> "$MANIFEST_FILE"
echo "  \"file_sha256\": \"$FILE_SHA256\"," >> "$MANIFEST_FILE"
echo "  \"softpaq\": \"$SOFTPAQ\"," >> "$MANIFEST_FILE"
echo "  \"title\": \"$TITLE\"," >> "$MANIFEST_FILE"
echo "  \"scope\": \"$SCOPE\"" >> "$MANIFEST_FILE"
echo "}" >> "$MANIFEST_FILE"

# Hand off to analysis
if [[ -x scripts/linux/analyze-hp-packages.sh ]]; then
    ./scripts/linux/analyze-hp-packages.sh "$EXTRACT_DIR" "$PKG_ID"
fi

echo "Import and initial extraction complete."
echo "Review ${MANIFEST_DIR} before promoting to reference TSVs."
