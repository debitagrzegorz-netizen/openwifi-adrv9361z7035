# Release v1.1 (local)

v1.1 is the first image built entirely from sources, hardware and software
in one command. It replaces v1.0, which used a supplied XSA. This release is
local: it is tagged in the source tree and the forks, and nothing is
published.

## Image

| File | SHA256 |
|---|---|
| `openwifi-adrv9361z7035.wic` | `ca0fff593b4f5f731552397e5951b4acf9f04fcbdd652bac2a4bd3b55f56c676` |
| `BOOT.BIN` | `5a5442d2d61e714a9f23bbaf55916bd07a4668b0c81f85ce5c3d8f62418e2d7c` |
| `system.bit` | `f4315add10dbf6fbec79904eef4a78d7ebafa6ac87925ce75ad4e843fa1e2de3` |
| `system.dtb` | `b0fbcc7b99be84cddad7d72575b763358c0a3842604db83b6567a6a67df60f06` |
| XSA (hw stage) | `8a84bf5b9b014cb2b098bad9c3e70de5abf9e90ff34702f380da0549caa31134` |

The XSA is a zip with build timestamps, so its hash differs on every build.
The image gates compare the bitstream payload instead.

On target: kernel `6.12.0adi-v2025.1-27765-g895105ce6236`, xpu git rev
register `0x0EDBAB1C`, USR_ACCESS `0x264cd5ac`. `/etc/openwifi-build-info`
lists every input revision below.

## Input revisions

| Input | Revision |
|---|---|
| This tree (image built from) | `47ce830` |
| openwifi (driver) | `08827d58b23ea8c2300279196274a7a6174a4a1b` |
| openwifi-hw | `edbab1ce8644830e29fa4654b0a07dc53531b857` |
| ADI hdl | `65ad1e7c17227cd98283e48b5acb305132ee2542` |
| openofdm_rx | `2bb3ad1a1f0023bfd15168db4e196ebf0d56d76c` |
| meta-adi | `10578f90e0fb521279aed64c69271eb3b6448cb3` |
| ADI Linux (`LINUX_ADI_REV`) | `65fe8440a8500a776425b47800a1b3e8a9381ae4` |
| libiio (`LIBIIO_REV`) | `a01d323d0e7af3cefc2e8e0c68ce40e5bbeabca1` |
| Tools | Vivado, Vitis and PetaLinux 2025.1 |

The tag `v1.1` points at `47ce830`, the commit the image was built from.
Later commits change only tests and documentation:

- `084ba3b`: the F2 identity row checks a post-v1.0 image against its own
  pins (it still expected the v1.0 xpu git rev and XSA).
- `d2e40dc`: F8 warms up the host-to-board direction before the scored
  echoes. The gate is unchanged.
- The release documentation commit that adds this file.

Local tags (annotated, not pushed):

| Repository | Tag | Commit |
|---|---|---|
| this tree | `v1.1` | `47ce830` |
| openwifi | `adrv9361z7035-2025.1-v1.1` | `08827d5` |
| openwifi-hw | `adrv9361z7035-2025.1-v1.1` | `edbab1c` |

## Changes since v1.0

- **SDT flow.** The Linux image is built from a System Device Tree project
  that `build.sh` creates (`docs/SDT-NOTES.md`).
- **One-command build.** `./build.sh all` builds the FPGA (`hw/build_hw.tcl`)
  and then the software image from an empty clone in about 50 minutes. The
  hw stage hashes its inputs per stage and checks the sub-IP configuration
  against v1.0.
- **TX clock-domain-crossing fix** (openwifi-hw `edbab1c`). The TX sample
  bus into the DAC clock domain now goes through an `xpm_fifo_async`. The
  old bus could launch on the capture edge after a reset, depending on the
  phase between the two clocks. This adds a constant latency of about
  160 ns and does not change ACK timing.
- **Viterbi decoder data format.** The sub-IP is generated with the
  `Offset_Binary` format that v1.0 used.
- **side_ch fixes.** The module reloads on kernel 6.12, and CSI and IQ
  capture can alternate without a reload.
- **Lost-wake fix** (openwifi `54e77c2`). A TX completion between the unlock
  and the queue stop could leave a mac80211 queue stopped for good. The
  driver now checks again after it stops the queue.
- **Driver TX watchdog and recovery** (`54e77c2`, `08827d5`). See
  `docs/KNOWN-ISSUES.md` (FPGA TX-queue freeze) and `docs/TESTING.md`.
  - A frozen FPGA TX queue is detected after 1.25 s and recovered in place.
  - A TX descriptor that can no longer complete is retired after 1 s.
- **Kernel and libiio pins.** meta-adi builds both with AUTOREV. They are
  now pinned in `config/versions.conf` (`docs/BUILD.md`).

## Validation

All on the bench board (ADRV9361-Z7035 on ADRV1CRR-BOB, RT3572 client at
30–50 cm, channel 13, client 5 dBm).

Release soak:

| Block | Result |
|---|---|
| A, 100 AP start/stop cycles with association and traffic | 100/100 |
| B, 30 driver reloads (`wgd.sh`) | 30/30 |
| C, 3 × 90 min continuous TCP in 5-min segments | 54/54 segments. c2ap median 23.8 (22.9–25.8) Mbit/s, ap2c median 22.9 (19.0–23.0) Mbit/s. No segment below 20 / 17 |
| D, 10 soft reboots | 10/10, 35–37 s each |

In the whole soak there were 0 hangs, resets or kernel fault lines, and 0
stalls that needed a reload.

Block C saw 3 FPGA TX-queue freezes. The driver recovered all of them, each
detected after 1250 ms with 60–73 frames retired. The TCP stream of the
segment kept 23.6–24.4 Mbit/s, and the next board-to-client segment was
clean. The v1.0 bitstream showed 2 freezes in the same 4.5 h test.

Feature matrix (`tests/feature_matrix.sh --image sdt`):

| Rows | Result |
|---|---|
| F1–F4, F7–F16, F20 | PASS |
| F5 | PASS. Ping 1/900 lost; c2ap median 23.3 (minimum 22.8) Mbit/s; ap2c median 22.8 (minimum 22.6) Mbit/s; UDP loss at most 0.016 % |
| F6 | PASS(info): ping loss 2–3 % on channels 1 and 6, with a neighbour network on channel 3 |
| F17 | FAIL, accepted as a known issue (`docs/KNOWN-ISSUES.md`) |
| F18, F19 | KNOWN-ISSUE |
| F21 | SKIPPED (no 5 GHz approval) |

In every row the driver TX watchdog recorded no detection, recovery or
retired descriptor. This is the second full matrix: the first one failed
F5 (one slow run), F8 (the first echo after the IBSS join, fixed in the
harness by `d2e40dc`) and F17.

## Rollback

Write the v1.0 image back to the SD card. v1.1 needs no host-side change.
