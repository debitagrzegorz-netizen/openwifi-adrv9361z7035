# Known issues

- High-order transmit (16-QAM and 64-QAM, and the matching HT rates) fails on
  the paused from-scratch FPGA bitstream. The v1.0 bitstream receives those
  rates. This tree does not rebuild or load that bitstream.
- F18 stays KNOWN-ISSUE. The mac80211 TX-power hook is in the driver.
  A before/after attenuation measurement on a booted image is still required.
- Client power-save ping is KNOWN-ISSUE (F19). The previous power-save driver
  change was reverted.
- CSI capture on the v1.0 card previously delivered 0 UDP bytes. F16 records
  the byte count and does not load a side_ch module that is not the fixed one.
- 5 GHz is not enabled. There is no APPROVED-REG.
- The v1.0 rootfs has no `/etc/openwifi-build-info`. F2 on that card fails
  that part of the row. The SDT image writes the file.
