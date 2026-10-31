# License map

| Path | License | Notes |
|---|---|---|
| `build.sh`, `sw/sdt/gen_sdt.sh`, `scripts/`, `tests/` | AGPL-3.0-or-later | New files for this port |
| `sw/meta-openwifi` recipes | AGPL-3.0-or-later, GPL-2.0-or-later, MIT | Per-recipe `LICENSE` |
| `0001-ad9361-export-openwifi-helpers.patch` | GPL-2.0-only | Linux kernel change |
| openwifi driver and `user_space` (fetched) | AGPL-3.0-or-later | Upstream `LICENSE` |
| `inject_80211` (fetched) | GPL-2.0-or-later | Upstream header |
| ADI kernel and meta-adi (external) | GPL-2.0 and the ADI layer licenses | Not vendored here |
| Device-tree fragments | GPL-2.0-only | Same as the kernel DTS they extend |

A publication pass still has to run a license scanner and confirm every file.
This table is the intended map, not that scan.
