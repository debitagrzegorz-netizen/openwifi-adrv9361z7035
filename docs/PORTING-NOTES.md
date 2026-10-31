# Porting notes

Pinned revisions are in `config/versions.conf`. The driver branch is
`adrv9361z7035-2025.1` at openwifi `75ab6fe`.

## Already in that driver commit

These are not shipped as recipe patches, because they do not apply on top of
`75ab6fe`:

- P12 TX lock sanity (`openwifi_tx_lock_sanity` in `sdr.c`, and the Makefile
  object list).
- side_ch first-DMA fix for 6.12 (`chan_to_ps_cookie != 0`).
- `USE_NEW_RX_INTERRUPT` is already 1 in `pre_def.h`.
- `monitor_ch.sh` uses `iw` when `iwconfig` is absent.
- `tx_stat_show.sh` and `rx_stat_show.sh` already fall back from `fpga-axi@0`
  to `soc0/axi`.

`sdr.c` assigns `.testmode_cmd` unconditionally. The kernel fragment
`openwifi.cfg` sets `CONFIG_NL80211_TESTMODE=y`, so the build does not need
`-Wno-implicit-function-declaration`.

## Recipe patches that do apply

- `wgd.sh`: load `xilinx_dma` with `modprobe` (the AD9361 driver is built in).
- `wgd.sh`: print `/etc/openwifi-build-info`, the xpu git revision at
  `0x83C400FC`, and USR_ACCESS when sysfs exposes it.
- `load_fpga_img.sh`: the board load path used by this port.
- Kernel: `0001-ad9361-export-openwifi-helpers.patch` exports
  `ad9361_set_tx_atten`, `ad9361_get_tx_atten`, `ad9361_ctrl_outs_setup`, and
  `ad9361_do_calib_run`. It is a real patch against the unmodified ADI
  `ad9361.c`. A failed apply fails the build. It does not include other edits
  that exist only in a previous work tree.

`GIT_REV` in `git_rev.h` is the first eight hex digits of `SRCREV`.

The image blacklists `side_ch` so the OF modalias does not load it, and still
symlinks the module for `wgd.sh` and for an explicit `insmod`.

## Device tree

Strategy B is recorded in `docs/SDT-NOTES.md`. One device-tree bbappend carries
`system-user.dtsi`, `openwifi.dtsi`, `openwifi-adi-cleanup.dtsi`, and the
pl-delete file. The GEM MAC in `system-user.dtsi` is the design MAC
`00:0a:35:00:1e:53`.
