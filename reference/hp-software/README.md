# HP Software Archaeology

This directory contains metadata, hashes, source URLs, public hardware IDs, and analysis notes derived from HP's publicly distributed Windows ARM64 software for the target SKU.

## Proprietary Content Policy
The repo tracks ONLY metadata. The repo does NOT redistribute:
- HP SoftPaq binaries
- Windows drivers
- firmware blobs
- extracted proprietary packages

The user must fetch packages from HP directly using the provided `scripts/linux/fetch-hp-packages.sh`.

## Scope
Software candidate evidence is strictly marked `HP-SOFTWARE` and must not be confused with `OBSERVED` hardware evidence.
