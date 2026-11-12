# openwifi on ADRV9361-Z7035

A port of [open-sdr/openwifi](https://github.com/open-sdr/openwifi) (an
open-source IEEE 802.11 Wi-Fi baseband on FPGA) to the Analog Devices
ADRV9361-Z7035 SOM on the ADRV1CRR-BOB carrier. It is built with AMD Vivado
and PetaLinux 2025.1. One command builds the FPGA and the Linux SD-card image
from sources.

Current release: **v1.2.1** (`docs/RELEASE-v1.2.1.md`): v1.2 plus the
published-build glue, the pyadi-iio pin and documentation. The image content
and the FPGA design are those of **v1.2** (`docs/RELEASE-v1.2.md`). Previous
release: v1.1 (`docs/RELEASE-v1.1.md`).

> These repositories are private until the owner publishes them.

## Repositories

| Repository | What |
|---|---|
| this repository | build scripts, hardware build in Tcl, PetaLinux layer `meta-openwifi`, tests, docs |
| [openwifi-adrv9361z7035-openwifi](https://github.com/debitagrzegorz-netizen/openwifi-adrv9361z7035-openwifi) | the openwifi driver and userspace, branch `adrv9361z7035-2025.1` (based on open-sdr/openwifi) |
| [openwifi-adrv9361z7035-openwifi-hw](https://github.com/debitagrzegorz-netizen/openwifi-adrv9361z7035-openwifi-hw) | the FPGA design, branch `adrv9361z7035-2025.1` (based on open-sdr/openwifi-hw) |

`build.sh` fetches both, plus ADI hdl, openofdm and meta-adi, at the
revisions pinned in `config/versions.conf`.

## Hardware

- SOM: ADRV9361-Z7035 (Zynq xc7z035, AD9361, 40 MSPS)
- Carrier: ADRV1CRR-BOB
- Antennas: SOM U.FL RX1A and TX1A (device-tree port select 0)
- 2.4 GHz only (5 GHz is not enabled)

## v1.2 results

All on the bench board, with an RT3572 USB client at 30–50 cm, channel 13, and
the client at 5 dBm.

- **FPGA TX-queue freeze fixed in the hardware.** In 4.5 h of continuous TCP
  (54 segments of 5 min) there were 0 freezes, against 3 on v1.1. Client to
  AP: median 23.6 Mbit/s (23.2–25.0). AP to client: median 22.9 Mbit/s
  (22.3–23.1).
- **Feature matrix.** Every gate row passes in three full runs (Ubuntu 22.04
  and twice on Ubuntu 24.04). The link test F5 is three runs of 300 pings and
  10 s TCP/UDP tests:

| Run | Pings lost | TCP client→AP median / min (Mbit/s) | TCP AP→client median / min | UDP loss max |
|---|---|---|---|---|
| Ubuntu 22.04 host | 1/900 | 24.4 / 23.0 | 23.1 / 23.0 | 0.016 % |
| Ubuntu 24.04 host, run 1 | 1/900 | 23.1 / 22.1 | 22.6 / 20.5 | 0 |
| Ubuntu 24.04 host, run 2 | 0/900 | 24.5 / 23.2 | 23.1 / 22.9 | 0.016 % |

Details and all image hashes: `docs/RELEASE-v1.2.md`.

## Quick start (with a built image)

The v1.2 release does not ship the SD-card image (see
[FPGA images and licences](#fpga-images-and-licences)). Build it first, as
described below. Then:

1. Write `build/images/openwifi-adrv9361z7035.wic` to an SD card. Use
   `./build.sh flash --device /dev/sdX --yes`, or
   `bmaptool copy openwifi-adrv9361z7035.wic /dev/sdX`.
2. Boot the board. It takes an address by DHCP on Ethernet and announces
   itself as `openwifi.local`. Log in as `analog` over SSH or on the UART
   (115200 8N1).
3. **Change the default password on first boot** (`passwd`). The image keeps
   the ADI Kuiper default user `analog` with its well-known password.
4. Start openwifi:
   ```
   sudo mount -t debugfs none /sys/kernel/debug
   cd ~/openwifi && sudo ./wgd.sh
   ```
   This loads the driver, brings up `sdr0` and sets the AD9361 to 40 MSPS.
5. Start an access point (the image ships `hostapd-openwifi-2g.conf`, SSID
   `openwifi`, channel 6, and `dnsmasq-sdr0.conf` for DHCP on 192.168.13.0/24):
   ```
   sudo ip addr add 192.168.13.1/24 dev sdr0
   sudo hostapd -B ~/openwifi/hostapd-openwifi-2g.conf
   sudo dnsmasq --conf-file=$HOME/openwifi/dnsmasq-sdr0.conf
   ```

## Full build

Requirements:
- Ubuntu 24.04 LTS (supported; 22.04 is validated up to v1.2);
- AMD Vivado, Vitis and PetaLinux 2025.1;
- a **Vivado licence that includes the Viterbi Decoder IP**, either the
  evaluation licence (as upstream openwifi uses) or a full licence;
- about 120 GB free.

`tools/check_host.sh` checks the host prerequisites read-only. Then:

```
cp config/local.conf.example config/local.conf
# fill in TOOLS_ROOT, DL_DIR and SSTATE_DIR
./build.sh all
```

`all` runs hw, fetch, sdt, plnx-create, sw and image, in about 50 minutes. It
does not flash and does not run the on-board tests. The sources are cloned
from the URLs in `config/versions.conf`. Set a local clone path in
`config/local.conf` to override one. See `docs/BUILD.md`.

The FIT image keeps two device trees. `system-top.dtb` is the default boot
configuration. `zynq-adrv9361-z7035-bob.dtb` is the in-kernel board tree that
`system-top` is assembled from.

## Testing

`tests/feature_matrix.sh --image sdt` runs the on-air feature matrix against
the board from a Linux host with an RT3572 USB Wi-Fi client. It covers
identity, bring-up, link quality (F5 gate), channels, monitor mode and
injection, IBSS, side channel, TX power and soft reboots. See
`docs/TESTING.md` for the gates and the bench notes. In short: the client
joins at 5 dBm, the harness waits until the client is not scanning, and a
row the host radio could not run is `BENCH`, not a pass. Do not open the
desktop Wi-Fi panel or press the laptop's Wi-Fi key during a run.

## Known issues

See `docs/KNOWN-ISSUES.md`. The main ones:
- side-channel CSI/IQ capture (F16/F17) passed on the Ubuntu 24.04 bench
  only; this stays open for v1.3;
- clients in power save see some ping loss;
- a 20 dBm client closer than 0.5 m saturates the receiver;
- 5 GHz is not enabled.

## FPGA images and licences

Scripts and build glue here are AGPL-3.0-or-later. The openwifi driver and
FPGA design are AGPL-3.0 with the upstream dual-licence note. See `LICENSE`
and `LICENSES.md`.

The FPGA design uses the AMD/Xilinx Viterbi Decoder LogiCORE IP, which is
licensed by AMD per user. Bitstream-containing files (`system.bit`,
`BOOT.BIN`, the WIC image, the XSA) are **not** distributed with v1.2. Their
distribution depends on the terms of the AMD Core License Agreement for that
IP. Build them yourself with `./build.sh all`.

## Credits

- [open-sdr/openwifi](https://github.com/open-sdr/openwifi) and
  [open-sdr/openwifi-hw](https://github.com/open-sdr/openwifi-hw), by Xianjun
  Jiao and the openwifi contributors.
- [Analog Devices](https://github.com/analogdevicesinc): the HDL reference
  designs, Linux, libiio and meta-adi.

## Disclaimer

This is an independent port. It is not affiliated with or endorsed by AMD,
Analog Devices or open-sdr. Use it at your own risk and within your local
radio regulations.
