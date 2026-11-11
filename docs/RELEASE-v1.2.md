# Release v1.2 (local)

v1.2 fixes the FPGA TX-queue freeze in the hardware. Under sustained
traffic, v1.0 and v1.1 sometimes parked a TX queue, and the v1.1 driver
watchdog had to recover it. The image is built from sources in one command,
as v1.1 was. This release is local: it is tagged in the source tree and the
forks, and nothing is published.

## Image

| File | SHA256 |
|---|---|
| `openwifi-adrv9361z7035.wic` | `3b3589bedcca3b578a2f08bebebc5c19120505c454830df7d294c5256194c58e` |
| `BOOT.BIN` | `62b01deee85bafb2c19cc09e115b875d33869de1b8425c8343c847ba0217e950` |
| `system.bit` | `871b19bd766740f875ba72101d3e3efff1dd6c67aa3a9fcb718cf17219eff3cb` |
| `system.dtb` | `b0fbcc7b99be84cddad7d72575b763358c0a3842604db83b6567a6a67df60f06` |
| XSA (hw stage) | `e88b6d783fb0184cabb73415ffc91e9e1388541671f35f08fefa550bf82b71d0` |
| `sdr.ko` (installed in the image) | `4750cbdbe3bff9935c381fec8cc6a81b460120b35c7b7fa34bd435c22efad7be` |

The XSA is a zip with build timestamps, so its hash differs on every build.
The image gates compare the bitstream payload instead.

On target:
- kernel `6.12.0adi-v2025.1-27765-ge742ea456e2d`;
- xpu git rev register `0x049E8CEB`, USR_ACCESS `0x5b486827`;
- hw build: WNS 0.552 ns, WHS 0.013 ns, 41 999 LUTs, 56 918 FFs;
- `/etc/openwifi-build-info` lists every input revision below and the
  bitstream and XSA hashes (built 2026-11-06T09:41:38Z).

The image was built clean-room on Ubuntu 22.04. A clean-room rebuild of the
same sources on Ubuntu 24.04 is equivalent: BOOT.BIN, system.dtb, the
bitstream payload and all code sections are identical. Only timestamps, build
paths and the kernel version hash differ (`docs/BUILD.md`).

## Input revisions

| Input | Revision |
|---|---|
| This tree (image built from) | `009d99d` |
| openwifi (driver) | `08827d58b23ea8c2300279196274a7a6174a4a1b` (same as v1.1) |
| openwifi-hw | `49e8ceb4fc3ef6d0ccd4f1db2d3e9855962f153e` |
| ADI hdl | `65ad1e7c17227cd98283e48b5acb305132ee2542` |
| openofdm_rx | `2bb3ad1a1f0023bfd15168db4e196ebf0d56d76c` |
| meta-adi | `10578f90e0fb521279aed64c69271eb3b6448cb3` |
| ADI Linux (`LINUX_ADI_REV`) | `65fe8440a8500a776425b47800a1b3e8a9381ae4` |
| libiio (`LIBIIO_REV`) | `a01d323d0e7af3cefc2e8e0c68ce40e5bbeabca1` |
| Tools | Vivado, Vitis and PetaLinux 2025.1 |

The tag `v1.2` points at `009d99d`, the commit the image was built from.
Later commits change only tests, tools and documentation; none of them is in
the image:

- `9ae7fff`: F18 measures the TX power limit with the AP up and restores it
  (scored row, no gate change).
- `0df0102`: `docs/BUILD.md` (Ubuntu 24.04 supported build host, 22.04
  validated up to v1.2, test-bench host notes) and `tools/check_host.sh`.
- `d3d0131`: the test harness for the Ubuntu 24.04 / kernel 7.0 bench host
  (see below).
- `f53c66d`: the F1 UART probe sets 115200 8N1 raw itself and reads with a
  timeout.
- The release documentation commit that adds this file.

Local tags (annotated, not pushed):

| Repository | Tag | Commit |
|---|---|---|
| this tree | `v1.2` | `009d99d` |
| openwifi | `adrv9361z7035-2025.1-v1.2` | `08827d5` |
| openwifi-hw | `adrv9361z7035-2025.1-v1.2` | `49e8ceb` |

The local working clone of openwifi-hw carries two local build arrangements:
- `adi-hdl` is a symlink to the pinned ADI hdl checkout (`65ad1e7c1`);
- the `ip/openofdm_rx` submodule has the two documented patches applied: a
  Vivado 2025.1 `rot_lut` hook after `upgrade_ip`, and a simulation-only
  testbench initialisation.

These are working-clone local build arrangements, not in the image. The image
comes from a clean-room build (`openwifi_hw_dirty=0` in the hw build info),
and the WIC is bit-identical to that build.

## Changes since v1.1

- **FPGA TX-queue freeze fixed in the hardware** (openwifi-hw `49e8ceb`).
  - Root cause: a one-clock `quit_retrans` pulse could be lost, which parked
    the TX scheduler in `WAIT_CHANCE` with no backoff running.
  - Fix: `tx_bit_intf.v` restarts the backoff when it enters `WAIT_CHANCE`
    from `WAIT_TX_COMP`.
  - The driver watchdog of v1.1 (detect after 1.25 s, recover in place) stays
    as a safety net. Its counters are in `tx_stall_stat`.
- **F18 is a scored row.** It measures the TX attenuation with the AP up
  (0 → −10 → 0 dB) and restores `auto`. The old row left the AP at 10 dBm
  for every later row. Tests only, after the image (`9ae7fff`).
- **Ubuntu 24.04 build host.** 24.04 is the supported build host. The 24.04
  clean-room build of these sources is equivalent to the 22.04 one (see
  above). `tools/check_host.sh` checks the host prerequisites read-only.
- **Test harness for the 24.04 / kernel 7.0 bench** (`d3d0131`, `f53c66d`).
  No row, threshold or gate changed.
  - TX power: the host test radio's phy limit is set as well as the
    per-interface limit, and 5.00 dBm is checked.
  - Monitor mode: a managed+up step before every switch to monitor mode
    (kernel 7.0 otherwise leaves the RT3572 deaf to OFDM frames).
  - F10/F11 check that the host radio receives before they score. If it
    does not, the row is `BENCH`, never PASS.
  - The client joins at 5 dBm. At 20 dBm and 30–50 cm the board's receiver
    saturates.
  - Before a measured row the harness waits until the test radio is not
    scanning. An off-channel scan during a measurement loses about half of
    the AP's frames.
  - Each report has a bench-evidence section per row: power save, Wi-Fi
    rfkill, the GNOME Settings process, scan events and the scan wait. It is
    informational and never scored.
  - NetworkManager autoconnect of the test radio is turned off for a run and
    restored afterwards.
  - The F1 UART probe sets the console line itself and cannot block.

## Validation

All on the bench board (ADRV9361-Z7035 on ADRV1CRR-BOB, RT3572 client at
30–50 cm, channel 13, client 5 dBm).

Freeze fix, 4.5 h of continuous TCP (block C, 3 × 90 min in 5-min segments,
live load of the production bitstream):

| Item | v1.1 (`edbab1c`) | v1.2 (`49e8ceb`) |
|---|---|---|
| Segments OK | 54/54 | **54/54** |
| FPGA freezes (driver recoveries) | 3 | **0** (`stall_detect` 0, retired 0) |
| c2ap Mbit/s, median (min–max) | 23.8 (22.9–25.8) | 23.6 (23.2–25.0) |
| ap2c Mbit/s, median (min–max) | 22.9 (19.0–23.0) | 22.9 (22.3–23.1) |
| Hangs, kernel fault lines | 0 | 0 |

The fix had earlier been proven on a debug bitstream: 6 h of c2ap with 3
lost pulses and 0 freezes, where the baseline froze on 2 of 2 lost pulses.

Feature matrix (`tests/feature_matrix.sh --image sdt`) on the v1.2 card:

| Row | Ubuntu 22.04, kernel 6.8.0-136, harness `9ae7fff` (2026-11-07) | Ubuntu 24.04, kernel 7.0.0-42, harness `d3d0131`, run 1 (2026-11-11) | same, run 2 |
|---|---|---|---|
| F1–F4, F7–F9, F12–F15 | PASS | PASS | PASS |
| F5 ping lost | 1/900 | 1/900 | 0/900 |
| F5 TCP c2ap median / minimum (gate ≥ 22 / ≥ 20) | 24.4 / 23.0 | 23.1 / 22.1 | 24.5 / 23.2 |
| F5 TCP ap2c median / minimum (gate ≥ 19 / ≥ 17) | 23.1 / 23.0 | 22.6 / 20.5 | 23.1 / 22.9 |
| F5 UDP loss, maximum (gate ≤ 0.1 %) | 0.016 % | 0 | 0.016 % |
| F6 | PASS(info) | PASS(info) | PASS(info) |
| F10, F11 | PASS | PASS (15 in 18/18 cells; 10/10/10/10) | PASS (same) |
| F16 | FAIL `arrivals=0` | PASS `arrivals=2` | PASS `arrivals=2` |
| F17 | FAIL `arrivals=0` | PASS `arrivals=11` | PASS `arrivals=2` |
| F18 | PASS | PASS | PASS |
| F19 | KNOWN-ISSUE | KNOWN-ISSUE | KNOWN-ISSUE |
| F20 | 10/10 | 10/10 | 10/10 |
| F21 | SKIPPED (no 5 GHz approval) | SKIPPED | SKIPPED |

Every gate row passes in all three matrices. In each, the driver TX watchdog
recorded no stall or orphan, and DDS_SEL was 2 on all four DAC channels
afterwards. F16/F17 stay an open item for v1.3 (`docs/KNOWN-ISSUES.md`):
they passed on the 24.04 bench, but they had failed on 22.04 and on v1.1,
and the cause of the change is not known.

## Rollback

Write the v1.1 image (`ca0fff59…`) back to the SD card. v1.2 needs no
host-side change.
