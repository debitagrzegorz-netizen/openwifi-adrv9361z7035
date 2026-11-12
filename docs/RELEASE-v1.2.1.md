# Release v1.2.1 (source-only)

v1.2.1 is v1.2 plus three things:
- the glue for building from the published repositories;
- a pin for pyadi-iio;
- documentation.

The FPGA design and the driver are unchanged: openwifi `08827d5` and
openwifi-hw `49e8ceb`, as in v1.2. Built from these sources, the image has
the same boot files as v1.2 (see "Build check").

This is a **source-only** release: no SD-card image, `BOOT.BIN` or bitstream
is distributed. To build it you need your own AMD Vivado 2025.1 licence that
includes the **Viterbi Decoder** LogiCORE IP, either an evaluation or a full
licence. See `README.md` and `LICENSES.md`.

## Changes since v1.2 (`009d99d`)

| Commit | Change |
|---|---|
| `9ae7fff` | F18 measures the TX power limit with the AP up and restores it (tests only; scored row, no gate change) |
| `0df0102` | `docs/BUILD.md`: Ubuntu 24.04 is the supported build host, 22.04 validated up to v1.2, test-bench host notes; `tools/check_host.sh` |
| `d3d0131` | Test harness for the Ubuntu 24.04 / kernel 7.0 bench host (RT3572 TX power, monitor mode, scan-idle wait, bench evidence); no gate change |
| `f53c66d` | F1: the UART probe sets 115200 8N1 raw itself and reads with a timeout |
| `043a6a8` | Release notes for v1.2 |
| `234834f` | Publication: `build.sh` fetches openwifi and openwifi-hw from the published repositories by default; host-path guard read from `config/local.conf` |
| `4267889` | Pin pyadi-iio (`PYADI_IIO_REV=4e4195da2e08a1ca89b52c1770b3c3c60d45ced0`); meta-adi builds it with AUTOREV otherwise |
| this release's docs commit | `docs/BUILD.md` "Bitstream reproducibility", this file, `docs/KNOWN-ISSUES.md` (F16/F17), `README.md` |

Not changed:
- the FPGA design (openwifi-hw `49e8ceb4fc3ef6d0ccd4f1db2d3e9855962f153e`);
- the driver (openwifi `08827d58b23ea8c2300279196274a7a6174a4a1b`);
- ADI hdl, openofdm_rx, meta-adi, ADI Linux and libiio: all at the v1.2 pins.

## Input revisions

| Input | Revision |
|---|---|
| openwifi (driver) | `08827d58b23ea8c2300279196274a7a6174a4a1b` |
| openwifi-hw | `49e8ceb4fc3ef6d0ccd4f1db2d3e9855962f153e` |
| ADI hdl | `65ad1e7c17227cd98283e48b5acb305132ee2542` |
| openofdm_rx | `2bb3ad1a1f0023bfd15168db4e196ebf0d56d76c` |
| meta-adi | `10578f90e0fb521279aed64c69271eb3b6448cb3` |
| ADI Linux (`LINUX_ADI_REV`) | `65fe8440a8500a776425b47800a1b3e8a9381ae4` |
| libiio (`LIBIIO_REV`) | `a01d323d0e7af3cefc2e8e0c68ce40e5bbeabca1` |
| pyadi-iio (`PYADI_IIO_REV`, new) | `4e4195da2e08a1ca89b52c1770b3c3c60d45ced0` |
| Tools | Vivado, Vitis and PetaLinux 2025.1 |

Tags:
- this repository `v1.2.1`;
- openwifi and openwifi-hw `adrv9361z7035-2025.1-v1.2.1`, at the same commits as their `-v1.2` tags.

## Build check (src `4267889`, on the v1.2 hardware output)

| Item | Result |
|---|---|
| `BOOT.BIN` | `62b01deee85bafb2c19cc09e115b875d33869de1b8425c8343c847ba0217e950` (= v1.2) |
| `system.bit` | `871b19bd766740f875ba72101d3e3efff1dd6c67aa3a9fcb718cf17219eff3cb` (= v1.2) |
| `system.dtb` | `b0fbcc7b99be84cddad7d72575b763358c0a3842604db83b6567a6a67df60f06` (= v1.2) |
| WIC (this build, not distributed) | `b9019602f88c7b985ad8fc0f2544d8a74c6cfeed280bf00099f8a2f413f8a4b0` |
| rootfs manifest | `pyadi-iio 0.0.19+git3+4e4195da2e`; otherwise identical to v1.2 apart from the kernel release name |
| kernel release | `6.12.0adi-v2025.1-27765-g22020e7ca464` (v1.2: `…-ge742ea456e2d`) |
| image gates | all PASS |

- **WIC hash:** the WIC differs from v1.2 only by build-dependent content: the kernel release name, timestamps and `/etc/openwifi-build-info`, which gains `pyadi_iio_srcrev`.
- **Kernel release name:** it contains a hash of the local kernel commit, which changes with every build. Making it reproducible is a v1.3 item.
- **pyadi-iio version string:** the `+gitN` counter (`+git3` here) comes from the build host's PR-server history, not from the source. Another host can print `+git0` for the same commit.

## Bitstream from these sources

Vivado routing is not fully deterministic from run to run (`docs/BUILD.md`,
"Bitstream reproducibility"). Most builds give configuration frames
identical to v1.2. A build from the published repositories gave an
alternative routing once. That variant met timing (WNS 0.552 ns, WHS
0.013 ns) and was validated on air (next section).

## Validation

All on the bench board (ADRV9361-Z7035 on ADRV1CRR-BOB, RT3572 client at
30–50 cm, channel 13, client 5 dBm, Ubuntu 24.04 host, kernel 7.0.0-42).
The v1.2 card was used; the alternative bitstream was live-loaded (no SD write).

| Check | Bitstream | Result |
|---|---|---|
| Feature rows F3–F15, F18 | alternative routing | every gate row PASS. F5 0/900 ping lost, TCP c2ap median 24.8 / min 23.4, ap2c 23.0 / 22.8 Mbit/s, UDP 0; F10, F11 PASS |
| F6 (channels 1/6/11) | both | PASS(info) on the alternative bitstream. Channel 1 also failed on the v1.2 bitstream in the same session (adjacent-channel neighbour), so it is the environment |
| TCP soak, 2 × 30 min, direction alternating every 5 min | alternative routing | 12/12 segments; c2ap min 23.6, ap2c min 21.1 Mbit/s; driver watchdog `stall_detect` 0, `orphan_detect` 0; 0 kernel fault lines |
| F16/F17 alone, A-B-A-B (v1.2, alternative, v1.2, alternative) | both | 8/8 PASS, 27–28 arrivals each |
| Route repeat: same inputs routed 5 more times | — | all 5 = v1.2 configuration frames (0 differing words); the alternative was 1 of 8 routes |
| Build check above (pyadi-iio pin) | v1.2 hw output | boot files identical to v1.2; manifest = v1.2 apart from the kernel release name |

The v1.2 validation (4.5 h freeze soak, three full matrices) applies
unchanged, because the design and the driver are the same
(`docs/RELEASE-v1.2.md`).

## Known issues

See `docs/KNOWN-ISSUES.md`. The main ones:
- **Side channel (F16/F17):** depends on run order and is open for v1.3. Both rows pass in isolation on both bitstreams, and can fail when run after the full row list.
- **Power save:** ping to an AP client in power save (F19) loses some pings.
- **Near field:** a 20 dBm client closer than 0.5 m saturates the receiver.
- **Adjacent channel:** a neighbouring network can raise ping loss (F6, informational).
- **Kernel release name:** not reproducible between builds.
- **5 GHz:** not enabled.

On first boot, change the default password of the `analog` user (`passwd`).

## Rollback

v1.2.1 changes no image content that matters on target. Any v1.2 or v1.1
image is a valid rollback.
