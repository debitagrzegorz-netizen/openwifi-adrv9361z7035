# SDT notes

## Documents used

- UG1144 (v2025.1): SDT is supported on Zynq-7000. Create with
  `petalinux-create project -n <name> --template zynq`, then
  `petalinux-config --get-hw-description <sdt>`. The FSBL is a multiconfig
  bare-metal build. SDT device trees have more nodes than DTG; override them
  from `system-user.dtsi`. DTG is scheduled for deprecation.
- UG1647 SDTGen: `set_dt_param -xsa <xsa> -dir <out> [-debug enable]` then
  `generate_sdt`. There is no AMD board DTS for ADRV9361, so the wrapper does
  not pass `-user_dts` or `-board_dts`. The installed `sdtgen` takes a
  positional Tcl file. It has no `-source` flag.
- SDTGen versus XSCT (Xilinx wiki) and the 2025.1 open-source notes
  (Scarthgap 5.0.8, kernel 6.12.10, U-Boot 2025.01).
- Lopper can render a Linux DT from an SDT. This tree does not use that path
  for the Linux DTB. See strategy B.
- ADI meta-adi device-tree page and the meta-adi `10578f9` sources:
  `KERNEL_DTB` selects the in-kernel board DTS. The bbappend copies that DTS
  over `system-top.dts`, includes `pl.dtsi`, appends the pl-delete file, and
  includes `system-user.dtsi`.

## S0 answers

1. meta-adi `10578f9` does not implement the SDT flow. Its recipes do not
   reference `sdt`, `SYSTEM_DTFILE`, `lopper`, or `XILINX_WITH_ESW`. The ADI
   board DTS `zynq-adrv9361-z7035-bob` and the AD9361 SPI node come from the
   ADI kernel via `KERNEL_DTB`. The programmable-logic nodes come from
   `pl.dtsi`, which PetaLinux imports from the SDT directory. A missing
   `KERNEL_DTB` is a warning during `petalinux-config --get-hw-description`,
   and a fatal error later if the `.dts` or the delete file is absent.
2. Strategy B. The SDT flow supplies the machine configuration, the FSBL, and
   U-Boot, which is the 2025.1 path UG1144 documents for Zynq-7000. The Linux
   DTB stays the ADI kernel DTS plus `pl.dtsi`, the OpenWiFi delete list, and
   `system-user.dtsi`. Strategy A (port the whole ADI board DTS into
   `system-user.dtsi` on top of a lopper Linux DT) is described by AMD for
   boards that have no vendor DTS integration. meta-adi does not provide that
   integration, and it would drift from the DTS that produced the v1.0 image.
   Parts of the ADI DTS that must survive: the AD9361 SPI node (compatible
   `adi,ad9361`, LVDS, 2rx-2tx, FDD, `adi,rx-rf-port-input-select = <0>`,
   `adi,tx-rf-port-input-select = <0>`, enable GPIOs), the I2C ADM1166, the
   GEM Ethernet MAC, SD, UART, and USB.
3. The reference is the v1.0 runtime DTB, decompiled to
   `sw/reference/v1.0-system.dts`. Critical map, in decimal: `/axi/sdr`
   interrupts `0 29 1 0 30 1 0 33 1 0 34 1`, DMA `0x80400000` `0 35 4 0 36 4`,
   DMA `0x80410000` `0 31 4 0 32 4`, I2C `0x41600000` `0 58 4`.

## What sdtgen emitted for the v1.0 XSA

One `system-top.dts` (so `petalinux-config --get-hw-description` can take the
directory), plus `pl.dtsi`, `pcw.dtsi`, `zynq-7000.dtsi`, `skeleton.dtsi`,
`ps7_init` sources, and `reexport.bit`. Warnings only: `clk_wiz_0` has no
`s_axi_aclk`, and `openwifi_ip_rx_intf_0` pin `s2mm_intr` is not connected.
The PL labels match the existing OpenWiFi delete list (`axi_ad9361`,
`misc_clk_*`, `axi_gpreg`, `axi_iic_main`, `axi_pz_xcvrlb`, both DMAs, tx/rx
intf, openofdm tx/rx, xpu, side_ch). SDT also adds `clocking0`, `clocking1`,
and `afi3`, which nothing kept references. Those nodes, and the extra
`amba_pl` bus, are deleted. OpenWiFi nodes are recreated under `&amba` by
`openwifi.dtsi`.

`reexport.bit` is not the boot bitstream. The image stage packages the
bitstream extracted from the input XSA.

## Attempt 1

`device-tree.bb:do_compile` failed. meta-adi appends the delete include onto
`${DT_FILES_PATH}/pl.dtsi`. The SDT flow does not create that file.
`sdt-artifacts` installs `pl.dtsi` under `/usr/share/sdt/${MACHINE}/`. The
append therefore created a one-line file. `system-top.dts` includes it
immediately after `/dts-v1/;`, and dtc reported a syntax error on
`/delete-node/` at `pl-delete-nodes-openwifi-adrv9361z7035-bob.dtsi:6`
because no node exists yet. The fix copies the sdt-artifacts `pl.dtsi` into
place in `do_configure:prepend`, before the delete include is appended. This
is not a switch to the DTG flow.

## Reviewed differences

pending first image
