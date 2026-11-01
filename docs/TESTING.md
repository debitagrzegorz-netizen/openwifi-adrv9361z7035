# Testing

```
./tests/run_regression.sh --matrix --image v1.0
```

The command writes `build/features/FEATURES-<image>-<date>.md` and `.json`.
Each row is PASS, PASS(info), FAIL, SKIPPED with a reason, or KNOWN-ISSUE.

Rules the harness enforces:

- The management Wi-Fi interface is only read, never reconfigured. Its
  `nmcli` line must be unchanged at the end.
- The test dongle is `TEST_RADIO_IF` from `config/local.conf`.
- Link tests start only after `iw` reports `txpower 5.00 dBm`. Power save is
  off except for F19.
- Channel 13 unless the row names another channel. No regulatory change is
  applied on the host. 5 GHz is skipped.
- F2 reads the four DAC muxes after `wgd.sh`. Before that script a cold
  boot reads 0. The required value is still `0x00000002` on all four.
- F13 writes `0x1234` and `0x5678` and expects those FPGA values. A following
  write of 0 must remove the `SYSFS` line. When the captured value was 0,
  the FPGA register is not required to return to 0. LBT still round-trips,
  including a restore of 0.
- F11 injects only after the board pcap file exists. The decoded-frame
  gate stays at least 5 per cell.
- F6 is PASS when ping loss is under 1 % and TCP is above 0. It is
  PASS(info) when TCP is above 0, ping loss is 1–3 %, and the scan recorded
  a network on a channel within four of the channel under test. A higher
  loss, or that loss with no such neighbour, is FAIL. Channel 13 uses the
  F5 numbers.
- F16 needs at least 18 UDP datagrams, each a multiple of 3792 bytes. F17
  needs at least 14 datagrams of 32768 bytes with `iq_len_init=4095`. A
  count of 0 bytes is FAIL. `wgd.sh` runs first. The GET starts only after
  register 20 shows one full frame: 474 words for CSI, 4096 words for that
  IQ length.
- `side_ch.ko` is inserted only when it is the fixed module. On the v1.0 card
  the file must match the known-good hash. A broken module is not inserted.
- F20 reboots a healthy board ten times. If SSH does not return, the run
  stops and asks for a power-cycle.
- SSH password comes from `SSHPASS` or from `OPENWIFI_VALIDATION_SH` at run
  time. It is not stored in this tree.

See `docs/FEATURES.md` for the rows.
