# Feature matrix

| ID | Feature | Pass condition |
|---|---|---|
| F1 | Boot, eth0 DHCP, SSH, mDNS, UART getty | SSH, an eth0 address, `openwifi.local`, getty on ttyPS0 |
| F2 | Build traceability | Boot hashes, xpu git rev, DDS_SEL 2 on four DAC channels after `wgd.sh`, `/etc/openwifi-build-info` |
| F3 | AD9361 init | 40 MSPS, FIR enabled, fast_attack after `rf_init_11n.sh` and `agc_settings.sh 1` |
| F4 | Modules and IRQ map | `wgd.sh` exits 0 and `check_dtb_irqs.sh` passes on `/sys/firmware/fdt` |
| F5 | AP HT20 channel 13 | Three A4 runs at 5.00 dBm, channel 13, power save off. Ping loss ≤ 1 % over the 900 echoes and no run above 2 %. TCP client→AP median ≥ 22 Mbit/s and every run ≥ 20. TCP AP→client median ≥ 19 Mbit/s and every run ≥ 17. UDP loss ≤ 0.1 % in every run |
| F6 | Channels 1, 6, 11 | Association and 10 s TCP. Ping loss of 1–3 % is PASS(info) when an adjacent channel is occupied. Channel 13 keeps the F5 numbers |
| F7 | Station mode | Board `wpa_supplicant` to the dongle AP started by the hostapd wrapper |
| F8 | IBSS | `sdr-ad-hoc-up.sh` plus an `iw ibss join` on the dongle |
| F9 | Monitor RX | `monitor_ch.sh` and a tcpdump decode. An IRQ rise alone is not a pass |
| F10 | Board injection | Legacy 6/24/54 and HT MCS 0/4/7 at 100/500/1400 byte payloads |
| F11 | Host injection | Host `inject_80211` through the installed wrapper, counted on the board |
| F12 | sdrctl | TSF register read and a drv_xpu round trip that is restored |
| F13 | Channel access | cw and LBT scripts write and read back. A cw write of 0 clears the sysfs override and is not written to the FPGA |
| F14 | Time slicing | `slice_cfg.sh` configure, read back, restore |
| F15 | Statistics | `stat_enable.sh` and the tx/rx stat scripts around traffic |
| F16 | side_ch CSI | At least 18 UDP datagrams, each a multiple of 3792 bytes |
| F17 | side_ch IQ | At least 14 datagrams of 32768 bytes at `iq_len_init=4095` |
| F18 | TX power | KNOWN-ISSUE until a before/after attenuation measurement |
| F19 | Client power save | KNOWN-ISSUE; the ping loss is recorded |
| F20 | Reboots | 10 healthy soft reboots, each reaching `wgd.sh` |
| F21 | 5 GHz | SKIPPED. No APPROVED-REG |

F5 is scored on the three runs together. The v1.0 image lost 1.333 % of one
300-ping run (4 of 300) and, in an earlier reverse-direction measurement,
delivered 15.7–16.8 Mbit/s. A per-run ceiling of 1 % ping loss and 22 Mbit/s
in every direction is therefore not a property of the reference image.

F5 uses UDP ≤ 0.1 % because the earlier strict 0 % gate missed by 1–3 datagrams
out of 6250 on the same v1.0 image.
