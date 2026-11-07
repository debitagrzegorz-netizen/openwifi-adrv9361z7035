# Known issues

## FPGA TX-queue freeze (recovered by the driver)

Under sustained traffic, an FPGA TX queue sometimes stops sending.

- **Signature.** Frames stay in the `tx_intf` queues (register 26 holds the
  per-queue counts, for example 47–59 on queue 2). The xpu shows the medium
  idle, and no TX interrupt arrives.
- **Since when.** It is pre-existing: the v1.0 bitstream shows it too (2 in
  4.5 h of continuous TCP). It is not caused by the v1.1 CDC fix.
- **Observed rate in v1.1.** The release soak had 3 freezes in 4.5 h of
  continuous TCP (block C), about one per 1.5 h. An earlier 4.5 h run had 0.
- **What v1.1 does.** The driver TX watchdog runs every 250 ms. It detects
  the freeze after 1.25 s: frames are pending, nothing completes, the medium
  is idle and no DMA is in flight. It then recovers in place:
  - it pulses the `tx_intf`, `openofdm_tx` and xpu TX resets,
  - it returns the pending frames to mac80211 as failed,
  - it wakes all queues.

  No module reload is needed and the TCP stream survives. All 3 soak
  recoveries completed in under 2 s.
- **Orphaned descriptors.** A TX descriptor older than `tx_wd_stall_ms` that
  can no longer complete is retired. Either its queue is completing newer
  frames, or its FPGA queue is empty with no DMA in flight. In the release
  soak this repair never had to act.
- **Counters.** Read `/sys/devices/soc0/axi/axi:sdr/tx_stall_stat`
  (`stall_detect`, `stall_recover`, `retired`, `orphan_detect`, ...) and
  `tx_ring_stat`. Writing 0 to `tx_stall_stat` clears the counters.
- **Tunables.** The module parameters are `tx_wd_period_ms` (default 250,
  0 disables the watchdog) and `tx_wd_stall_ms` (default 1000).
- **Root cause.** Open. It is planned for v1.2 with a debug bitstream that
  exposes the TX scheduler state.

## IQ capture (F17)

F17 (side_ch IQ capture, `iq_len_init=4095`) has not passed on the SDT image
in any matrix run. After `side_ch` is reloaded in IQ mode and the receiver
is retuned with `monitor_ch.sh sdr0 13`, the board's `rx_pkt_intr` count
barely moves (0–1 frames in 2 s) although an AP beacons on that channel.
The capture then cannot fill its frames. The CSI capture (F16) passes. This
predates the v1.1 changes. It is accepted as a known issue for v1.1 and
planned for v1.2. The matrix still reports F17 as FAIL.

## Other issues

- **TX power (F18), resolved in the harness.** `iw set txpower` works: a
  10 dBm limit gives −10 dB TX attenuation. The old F18 row set this limit and
  never removed it, so every later row ran with the AP 10 dB weaker; on a weak
  bench the client then scanned off channel and F5 lost about 27 % of pings.
  F18 now measures the attenuation with the AP up and restores `auto`. The
  `txpower` value that `iw dev sdr0 info` prints can lag the change, so the row
  scores the attenuation only.
- **AP power-save clients (F19).** Ping to a client in power save is
  KNOWN-ISSUE. The previous power-save driver change was reverted.
- **Near-field saturation.** At 30–50 cm a client at 20 dBm saturates the
  receiver. Link tests use 5 dBm.
- **Channel 3 neighbour (F6).** A nearby network on an adjacent channel can
  raise ping loss on channel 3. F6 then reports PASS(info).
- **SSH key login.** `/home/analog` is owned by root in the image, so
  `ssh-copy-id` cannot create `~/.ssh`. The test harness takes the password
  from the environment (`SSHPASS`) at run time.
- **5 GHz.** It is not enabled. There is no regulatory approval.
- **v1.0 card identity.** The v1.0 rootfs has no `/etc/openwifi-build-info`,
  so F2 on that card fails that part of the row. The SDT image writes the
  file.
- **CSI on the v1.0 card.** Capture there previously delivered 0 UDP bytes.
  F16 records the byte count and does not load a side_ch module that is not
  the fixed one.
