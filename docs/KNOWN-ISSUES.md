# Known issues

## FPGA TX-queue freeze — fixed in v1.2

Under sustained traffic, v1.0 and v1.1 sometimes parked an FPGA TX queue:
frames stayed in the `tx_intf` queues, the xpu showed the medium idle, and no
TX interrupt arrived (about one per 1.5 h of continuous TCP).

- **Root cause.** A one-clock `quit_retrans` pulse could be lost. The TX
  scheduler then stayed in `WAIT_CHANCE` with no backoff running.
- **Fix (v1.2, openwifi-hw `49e8ceb`).** `tx_bit_intf.v` restarts the backoff
  when it enters `WAIT_CHANCE` from `WAIT_TX_COMP`. A 4.5 h block C gave
  54/54 segments and 0 freezes (v1.1: 3).
- **The driver watchdog stays as a safety net.** It runs every 250 ms,
  detects a frozen queue after 1.25 s and recovers in place: it pulses the
  `tx_intf`, `openofdm_tx` and xpu TX resets, returns the pending frames to
  mac80211 as failed, and wakes all queues. A TX descriptor older than
  `tx_wd_stall_ms` that can no longer complete is retired.
- **Counters.** `/sys/devices/soc0/axi/axi:sdr/tx_stall_stat` (`stall_detect`,
  `stall_recover`, `retired`, `orphan_detect`, ...) and `tx_ring_stat`.
  Writing 0 to `tx_stall_stat` clears the counters. On v1.2 all release runs
  ended with `stall_detect` and `orphan_detect` at 0.
- **Tunables.** `tx_wd_period_ms` (default 250, 0 disables the watchdog) and
  `tx_wd_stall_ms` (default 1000).

## CSI and IQ capture (F16, F17) — open, planned for v1.3

On Ubuntu 22.04 (v1.1 and v1.2) both rows failed with `arrivals=0`: the RF
source was not heard before the capture was armed, so no frames were
captured. On the Ubuntu 24.04 bench with the kernel 7.0 harness, both rows
passed in both release matrices (F16 `arrivals=2` and 2, F17 `arrivals=11`
and 2). The cause of the change is not known. Candidates are the harness
changes in `d3d0131` (the client joins at 5 dBm, the scan-idle wait, the
monitor-mode step) or bench conditions. The rows stay an open item until
the result is reproduced and explained.

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
  receiver: about 1.5 retries per frame, the AP drops the client and DHCP
  times out. Link tests use 5 dBm, and the harness sets it before the client
  joins.
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

## Test bench host notes

These concern the host side of the bench, not the image.

- **Off-channel scans of the test radio.** If the client radio scans during a
  measurement, it leaves the channel about every 0.45 s, and the AP's frames
  sent meanwhile are lost. One full-band scan lost 117 of 1200 pings, and
  without the scan 0 of 1200 were lost. Ping replies and TCP ACKs suffer
  first, so a TCP test can drop to about 10 Mbit/s. The harness waits until
  no scan is in progress before a measured row and reports the scan events
  of every row.
- **Do not use the laptop Wi-Fi/airplane key or the GNOME Wi-Fi panel or
  quick-settings Wi-Fi menu during runs.** The key switches all Wi-Fi off and
  on (rfkill). The panel and the menu make NetworkManager scan with every
  Wi-Fi device, including the test radio.
- **Kernel 7.0 with rt2800usb (RT3572).** The per-interface TX power limit is
  not always applied, and a down/up in monitor mode leaves the radio deaf to
  OFDM frames. The harness handles both (`docs/BUILD.md`, `docs/TESTING.md`).
