# HP Software Archaeology

This directory contains metadata, hashes, source URLs, public hardware IDs, and analysis notes derived from HP's publicly distributed Windows ARM64 software for the target SKU.

## Official Sources

Official HP driver page:
https://support.hp.com/in-en/drivers/hp-omnibook-5-16-inch-laptop-next-gen-ai-pc-16-bf1000/2103480507

HP support-page product identifier:
2103480507

Product family:
HP OmniBook 5 16 inch Laptop Next Gen AI PC 16-bf1000

Source:
human-verified official HP support page

Evidence:
HP-SOFTWARE / FAMILY

**Target Product Number:** D3ZN3UA

## Proprietary Content Policy
The repo tracks ONLY metadata. The repo does NOT redistribute:
- HP SoftPaq binaries
- Windows drivers
- firmware blobs
- extracted proprietary packages

The user must provide packages manually to `.work/hp-software/incoming/` and use the provided `scripts/linux/import-hp-package.sh`.

## Scope
Software candidate evidence is strictly marked `HP-SOFTWARE` and must not be confused with `OBSERVED` hardware evidence.
