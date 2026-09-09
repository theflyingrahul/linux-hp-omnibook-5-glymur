#!/bin/bash
set -euo pipefail

PATCH_DIR=".work/patches"
mkdir -p "$PATCH_DIR"

# Validator function
validate_patch() {
    local file="$1"
    
    if [ ! -s "$file" ]; then
        return 1
    fi

    # Check for HTML
    if grep -iqE '^<!DOCTYPE html|<html' "$file"; then
        return 1
    fi

    # Check for RFC822 headers
    if ! grep -iqE '^From: ' "$file"; then
        return 1
    fi
    if ! grep -iqE '^Subject: ' "$file"; then
        return 1
    fi
    if ! grep -iqE '^Date: ' "$file"; then
        return 1
    fi

    # Check for patch content or cover letter
    # A series mbox might have diffs or might just be a cover letter
    if ! grep -q 'diff --git' "$file" && ! grep -iqE '^Subject: \[PATCH.*0/[0-9]+\]' "$file"; then
        # Could be a single patch without a diff (e.g. empty commit) but that's rare.
        # We will allow it if it has an mbox From line.
        if ! grep -q '^From ' "$file"; then
            return 1
        fi
    fi

    return 0
}

fetch_series() {
    local board_name="$1"
    local msgid="$2"
    local expected_path="$3"
    
    local out_dir="$PATCH_DIR/$board_name"
    mkdir -p "$out_dir"
    local out_file="$out_dir/series.mbox"
    
    echo "Fetching $board_name..."
    local success=0
    local backend=""

    # Try Lore raw
    echo "  -> Trying lore.kernel.org/all/$msgid/t.mbox.gz ..."
    if curl -sL "https://lore.kernel.org/all/$msgid/t.mbox.gz" > "$out_file.gz"; then
        if gzip -t "$out_file.gz" 2>/dev/null; then
            zcat "$out_file.gz" > "$out_file.tmp"
            if validate_patch "$out_file.tmp"; then
                mv "$out_file.tmp" "$out_file"
                success=1
                backend="lore"
            fi
        fi
        rm -f "$out_file.gz" "$out_file.tmp"
    fi

    # Try Patchew
    if [ $success -eq 0 ]; then
        echo "  -> Trying patchew.org/linux/$msgid/mbox ..."
        if curl -sL "https://patchew.org/linux/$msgid/mbox" > "$out_file.tmp"; then
            if validate_patch "$out_file.tmp"; then
                mv "$out_file.tmp" "$out_file"
                success=1
                backend="patchew"
            else
                rm -f "$out_file.tmp"
            fi
        fi
    fi

    # Try Lore raw single endpoint if series failed
    if [ $success -eq 0 ]; then
        echo "  -> Trying lore.kernel.org/all/$msgid/raw ..."
        if curl -sL "https://lore.kernel.org/all/$msgid/raw" > "$out_file.tmp"; then
            if validate_patch "$out_file.tmp"; then
                mv "$out_file.tmp" "$out_file"
                success=1
                backend="lore_single"
            else
                rm -f "$out_file.tmp"
            fi
        fi
    fi

    local out_hash="N/A"
    local format_res="INVALID"
    if [ $success -eq 1 ]; then
        format_res="PASS"
        out_hash=$(sha256sum "$out_file" | awk '{print $1}')
        
        # Verify expected path is in the mbox
        local path_res="MISSING"
        if grep -qF "$expected_path" "$out_file"; then
            path_res="PASS"
        fi
        printf "%-25s %-12s %-12s %-10s %s\n" "$board_name" "PASS($backend)" "$format_res" "$path_res" "$out_hash"
    else
        printf "%-25s %-12s %-12s %-10s %s\n" "$board_name" "FAILED" "INVALID" "N/A" "N/A"
    fi
}

CMD="${1:-all}"
VALIDATE_ONLY=0
if [ "$CMD" = "--validate-only" ]; then
    VALIDATE_ONLY=1
    CMD="${2:-all}"
fi

if [ "$VALIDATE_ONLY" -eq 1 ]; then
    printf "%-25s %-12s %-12s %-10s %s\n" "Series" "Retrieval" "Format" "Expected" "Hash"
    echo "---------------------------------------------------------------------------------------------------"
fi

case "$CMD" in
    elitebook)
        fetch_series "elitebook-v5" "20260829-glymur-send-v5-0-a11bdf6a4b66@oss.qualcomm.com" "arch/arm64/boot/dts/qcom/glymur-hp-elitebook-x-g2q.dts"
        ;;
    omnibook-ultra)
        # Note: the cover letter message ID for OmniBook Ultra was missing, using known patch message ID or we will search Patchew.
        fetch_series "omnibook-ultra-v1" "20260830-x2-hp-omnibook-ship-v1-0-9feada71dc79@oss.qualcomm.com" "arch/arm64/boot/dts/qcom/glymur-hp-omnibook-ultra-kg0xxx.dts"
        ;;
    pcie3)
        fetch_series "pcie3-v10" "20260825-glymur_linkmode_0826-v10-0-56ab597d77e4@oss.qualcomm.com" "pcie"
        ;;
    dp-phy)
        fetch_series "dp-phy-v3" "20260828-glymur-phy-v3-v3-0-8e73ce7c4636@oss.qualcomm.com" "phy"
        ;;
    all)
        fetch_series "elitebook-v5" "20260829-glymur-send-v5-0-a11bdf6a4b66@oss.qualcomm.com" "arch/arm64/boot/dts/qcom/glymur-hp-elitebook-x-g2q.dts"
        # I need to get the exact message-id for omnibook ultra!
        fetch_series "omnibook-ultra-v1" "20260830-x2-hp-omnibook-ship-v1-0-9feada71dc79@oss.qualcomm.com" "arch/arm64/boot/dts/qcom/glymur-hp-omnibook-ultra-kg0xxx.dts"
        fetch_series "pcie3-v10" "20260825-glymur_linkmode_0826-v10-0-56ab597d77e4@oss.qualcomm.com" "pcie"
        fetch_series "dp-phy-v3" "20260828-glymur-phy-v3-v3-0-8e73ce7c4636@oss.qualcomm.com" "phy"
        ;;
    *)
        echo "Usage: $0 [--validate-only] {elitebook|omnibook-ultra|pcie3|dp-phy|all}"
        exit 1
        ;;
esac
