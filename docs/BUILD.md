# Build

Requirements: Vivado, Vitis and PetaLinux 2025.1 (with a Viterbi Decoder
licence, see `LICENSES.md`), and shared `DL_DIR` / `SSTATE_DIR` if you do not
want a cold Yocto download.

The sources are fetched at the revisions pinned in `config/versions.conf`
from the URLs in the same file: the port branches of openwifi and openwifi-hw,
ADI hdl, openofdm and meta-adi. To build from a local clone instead, set its
path in `config/local.conf` (`OPENWIFI_REPO`, `OPENWIFI_HW_REPO`,
`ADI_HDL_REPO`, `OPENOFDM_RX_REPO`, `META_ADI_DIR`). A local clone must
contain the pinned revision. `HOST_PATH_GUARD` in `config/local.conf` lists
host path prefixes that the hw build must never find in its sources.

```
cp config/local.conf.example config/local.conf
./build.sh all
```

## Build host

| Host | Status |
|---|---|
| Ubuntu 24.04 LTS | **Supported build host** (from v1.2 on). A clean-room `./build.sh all` of the v1.2 sources gives an equivalent image: BOOT.BIN, system.dtb, the bitstream payload and all kernel and module code are bit-identical to the 22.04 build. The only differences are timestamps, build paths and the kernel version hash (see below). PetaLinux 2025.1 prints `[WARNING] This is not a supported OS` on 24.04. The warning is informational and the build continues. |
| Ubuntu 22.04 LTS | Validated up to v1.2 (history). It is a PetaLinux 2025.1 supported host and still works, but it is no longer the reference. |

Required host settings (both hosts):

- `/bin/sh` must be bash. PetaLinux refuses dash.
- On 24.04 (and Ubuntu 23.10 or later), AppArmor blocks the unprivileged
  user namespaces that bitbake needs. Set
  `kernel.apparmor_restrict_unprivileged_userns = 0` in a file under
  `/etc/sysctl.d/`.
- The `en_US.UTF-8` locale must be generated.
- The PetaLinux host packages must be installed. On 24.04, `libsdl1.2-dev`
  is called `libsdl1.2-compat-dev`.
- A clean-room build with cold native sstate needs about 120 GB free.
  `build.sh` stops below 30 GB.

`tools/check_host.sh [--dir <build dir>] [--bench]` checks these settings
read-only. It needs no sudo, changes nothing, and prints each missing item
with the command that fixes it. `--bench` also checks the tools the on-air
test harness uses. The exit status is 0 when the build prerequisites are met.

The kernel version string ends in `-g<hash>`. That hash is the commit
Yocto makes of the unpacked kernel source, so it changes with the build
time and the host's git identity even when the source tree is identical.
Compare the kernel tree hash and the code sections, not the version
string.

## Test bench host

The on-air harness (`tests/feature_matrix.sh`) is validated on Ubuntu 24.04
with the HWE kernel 7.0 and an RT3572 USB test radio (rt2800usb). The harness
handles the known quirks of this kernel and radio:

- The per-interface TX power limit is not always applied to an associated
  client, so the harness also sets the phy limit and checks the result.
- After a down/up in monitor mode the radio stops receiving OFDM frames. The
  harness brings the interface up once in managed mode before every switch to
  monitor mode, and the injection rows check that frames arrive before they
  score (otherwise the row is `BENCH`, never `PASS`).
- The client joins at the test power (5 dBm). At 20 dBm and 30-50 cm the
  board's receiver saturates.
- An off-channel scan of the test radio during a measurement loses about half
  of the AP's frames. The harness waits until no scan is in progress before a
  measured row and records the scan events of every row in the report.
- The harness turns off NetworkManager autoconnect for the test radio during a
  run and restores the recorded setting at the end.

During a run, do not open the GNOME Wi-Fi settings panel or the quick-settings
Wi-Fi menu, and do not press the laptop's Wi-Fi/airplane key. All of them make
the test radio scan or switch it off. The F1 console probe sets the UART
(`UART_DEV` in `config/local.conf`) to 115200 8N1 raw itself and gives up
after 3 s, so no manual `stty` is needed and a silent console cannot block
the run.

## Stages

`all` builds the FPGA first (`hw`) and then the software image. With
`--xsa <v1.0.xsa>` it skips `hw` and uses the supplied v1.0 XSA instead.

Stages, each idempotent and logged under `build/logs/<stage>.log`:

| Stage | Action |
|---|---|
| `hw` | `hw/build_hw.tcl`: the FPGA project, bitstream and XSA, with per-stage input hashes and the sub-IP equivalence check. |
| `fetch` | Check pinned revisions. Clone openwifi into `build/src/openwifi`. |
| `sdt` | `sw/sdt/gen_sdt.sh` runs `sdtgen` on the XSA. Fails if the XSA hash is neither v1.0 nor the one the `hw` stage recorded. |
| `plnx-create` | `petalinux-create --template zynq`, import the SDT, apply config, silentconfig, verify. |
| `sw` | `petalinux-build`, including the multiconfig FSBL. |
| `image` | `petalinux-package --boot`, WIC, gates, `SHA256SUMS`, `build-info.json`. |
| `gates` | Re-run the image gates without packaging. |
| `flash` | Requires `--device` and `--yes`. Refuses otherwise. |
| `test` | `tests/run_regression.sh --matrix`. |

`all` is hw + fetch + sdt + plnx-create + sw + image. It does not flash.

The Linux device tree is strategy B. See `docs/SDT-NOTES.md`.

Image gates:

1. Bitstream payload in `BOOT.BIN`, the FAT `system.bit`, and the XSA bitstream match.
2. `scripts/check_dtb_irqs.sh` on the final DTB.
3. Critical AD9361, IRQ, DMA, Ethernet, SD, UART, and USB nodes match the v1.0 reference, and `docs/SDT-NOTES.md` has reviewed the remaining diff.
4. `sdr.ko` vermagic matches the kernel release.
5. The rootfs contains the openwifi packages and the files `wgd.sh` needs, including `/etc/openwifi-build-info`.

## Pinned kernel and libiio

meta-adi builds the ADI kernel (`linux-xlnx`) and libiio with
`SRCREV = "${AUTOREV}"`. Without a pin, two builds a day apart can get
different kernels. The build is reproducible only with the pins in
`config/versions.conf`:

- `LINUX_ADI_REV`, the ADI Linux commit,
- `LIBIIO_REV`, the libiio commit.

`build.sh` writes both into the PetaLinux BSP configuration, and the
`meta-openwifi` bbappends apply them. Both values are recorded in
`build/images/build-info.json` and in `/etc/openwifi-build-info` on the
target.

To bump a pin on purpose:

1. Change the value in `config/versions.conf` and commit it on its own.
2. Run `./build.sh all` from a clean clone.
3. Check that `sdr.ko` vermagic matches the new kernel (image gate 4).
4. Run the full matrix (`docs/TESTING.md`) and the soak before you tag.
