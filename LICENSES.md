# Licenses

Scripts and build glue in this repository are AGPL-3.0-or-later unless the
file says otherwise. That covers `build.sh`, `sw/sdt/gen_sdt.sh`, `scripts/`,
and `tests/`. Kernel-side patches are GPL-2.0-only. Third-party components
keep their upstream licenses. The ADI kernel and meta-adi are external and
are not vendored in this tree. This file is an inventory of the recipes and
patches here, not the output of a license scanner, and it does not copy the
upstream license texts.

OpenWiFi sources come from the port branch `adrv9361z7035-2025.1` of
open-sdr/openwifi, based on upstream `f6674ee`. Release v1.2 uses
`08827d58b23ea8c2300279196274a7a6174a4a1b` (`OPENWIFI_REV` in
`config/versions.conf`). The FPGA design comes from the same branch of
open-sdr/openwifi-hw at `49e8ceb4fc3ef6d0ccd4f1db2d3e9855962f153e`, based on
upstream `d047d79`. Both are AGPL-3.0 with the upstream dual-licence note
(commercial licences from openwifi.tech).

## FPGA images and the Viterbi Decoder

The FPGA design instantiates the AMD/Xilinx Viterbi Decoder LogiCORE IP. This
IP is licensed per user by AMD and is not open source. Building the bitstream
needs a Vivado installation with a Viterbi Decoder licence: either the
evaluation licence, which upstream openwifi uses and which halts the decoder
after about 2 hours, or a full licence.

Bitstream-containing files (`system.bit`, `BOOT.BIN`, the WIC image, the XSA)
are not distributed with the v1.2 release. Distributing them depends on the
terms of the AMD Core License Agreement for the Viterbi Decoder. Build them
locally with `./build.sh all`. This tree contains no AMD IP source, netlist or
bitstream: the IP is generated from the Vivado installation at build time. The
port commits in openwifi-hw add none either. The openwifi-hw history inherited
from upstream open-sdr/openwifi-hw keeps upstream's own IP configuration files
(`.xci`) and prebuilt bitstreams for other boards, as upstream publishes them.

## Recipes

| Recipe | License of what this layer adds | Upstream |
|---|---|---|
| `openwifi-driver` | AGPL-3.0-or-later | openwifi `driver/` |
| `openwifi-userspace` | AGPL-3.0-or-later | openwifi `user_space/` scripts and FIR files |
| `openwifi-tools` | AGPL-3.0-or-later and GPL-2.0-or-later. `sdrctl_src/nl80211.h` is ISC. `inject_80211` is GPL-2.0-or-later, with `unaligned.h` GPL-2.0-only and `radiotap.c` GPL-2.0. `sdrctl` and `side_ch_ctl` are AGPL-3.0-or-later. | openwifi `user_space/` |
| `openwifi-net` | MIT | Written here: hostname, console, and mDNS helpers |
| `device-tree` append | GPL-2.0-only | Device-tree fragments for the Xilinx device-tree recipe and the ADI ADRV9361 DTS |
| `linux-xlnx` append | GPL-2.0-only | ADI/Xilinx linux-xlnx kernel configuration and one AD9361 export |
| `libad9361-iio` append | Unchanged upstream license | Analog Devices libad9361-iio `2264074505ad4911155c815104292c6fbf98f62c`. The append pins that revision and skips the test tree. |
| `fru-tools` append | Append metadata is MIT. Upstream license unchanged. | Analog Devices fru_tools `e98eae11db567c8c8b8076998a68ac8467e52646` |
| `avahi` append | Local `avahi-daemon.conf` only. Avahi itself stays LGPL-2.1-or-later. | Avahi |
| `init-ifupdown` append | Local `interfaces` fragment for the upstream recipe | Yocto init-ifupdown |
| `petalinux-image-minimal` append | Image assembly only | PetaLinux minimal image |
| `layer.conf` | MIT | This layer |

## Patches

| Patch | License | What it changes |
|---|---|---|
| `recipes-kernel/openwifi-driver/openwifi-driver/0001-mac80211-txpower-to-ad9361-atten.patch` | AGPL-3.0-or-later | openwifi `driver/sdr.c`. Maps a mac80211 TX power notification to the existing AD9361 attenuation call. |
| `recipes-kernel/linux/linux-xlnx/0001-ad9361-export-openwifi-helpers.patch` | GPL-2.0-only | Analog Devices `drivers/iio/adc/ad9361.c` in the 2025.1 kernel. Exports `ad9361_set_tx_atten` and `ad9361_get_tx_atten`. |
| `recipes-kernel/linux/linux-xlnx/openwifi.cfg` | GPL-2.0-only | Kernel config fragment. Builds cfg80211, mac80211, and the Xilinx DMA driver as modules. |
| `recipes-core/openwifi-userspace/files/wgd.sh.patch` | AGPL-3.0-or-later | openwifi `user_space/wgd.sh` |
| `recipes-core/openwifi-userspace/files/wgd-print-identity.patch` | AGPL-3.0-or-later | openwifi `user_space/wgd.sh` |
| `recipes-core/openwifi-userspace/files/load_fpga_img.sh.patch` | AGPL-3.0-or-later | openwifi `user_space/load_fpga_img.sh` |
| `recipes-core/openwifi-userspace/files/slice_cfg.sh.patch` | AGPL-3.0-or-later | openwifi `user_space/slice_cfg.sh`. Uses the current sdrctl slice commands. |
| `recipes-core/openwifi-userspace/files/sdr-ad-hoc-iw.patch` | AGPL-3.0-or-later | openwifi ad-hoc scripts. Uses `iw` instead of `iwconfig`. |

Device-tree sources under `recipes-bsp/device-tree/files/` (`system-user.dtsi`, `openwifi.dtsi`, `openwifi-adi-cleanup.dtsi`, `pl-delete-nodes-openwifi-adrv9361z7035-bob.dtsi`) are GPL-2.0-only and were written for this port.

`wic/openwifi-sd.wks` is build metadata covered by the repository AGPL-3.0-or-later statement.
