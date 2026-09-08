# Reference Build Dependencies

Research snapshot: 2026-09-08 13:30 UTC

## Glymur PCIe3 Base Enablement
- **Series:** PCIe3 PHY and PCIe3a controller nodes
- **Version:** v10
- **Upstream Classification:** compile-time dependency for OmniBook Ultra
- **Local reproduction:** PASS (2026-09-08). Compiling OmniBook Ultra v1 without this dependency fails as expected (`Label or path pcie3_phy not found`), and succeeds with it applied.

## Glymur DP/QMP Combo PHY
- **Series:** Rework DP PHY runtime configuration
- **Version:** v3
- **Upstream Classification:** runtime-only for DP output
- **Local compile test:** DTB builds without dependency: PASS
- **Local runtime test:** NOT TESTED
