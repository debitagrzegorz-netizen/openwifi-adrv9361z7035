# Testing

```
./tests/run_regression.sh --matrix --image v1.0
```

The command writes `build/features/FEATURES-<image>-<date>.md` and `.json`.
Each row is PASS, FAIL, SKIPPED with a reason, or KNOWN-ISSUE.

Rules the harness enforces:

- The management Wi-Fi interface is only read, never reconfigured. Its
  `nmcli` line must be unchanged at the end.
- The test dongle is `TEST_RADIO_IF` from `config/local.conf`.
- Link tests start only after `iw` reports `txpower 5.00 dBm`. Power save is
  off except for F19.
- Channel 13 unless the row names another channel. No regulatory change is
  applied on the host. 5 GHz is skipped.
- `side_ch.ko` is inserted only when it is the fixed module. On the v1.0 card
  the file must match the known-good hash. A broken module is not inserted.
- F20 reboots a healthy board ten times. If SSH does not return, the run
  stops and asks for a power-cycle.
- SSH password comes from `SSHPASS` or from `OPENWIFI_VALIDATION_SH` at run
  time. It is not stored in this tree.

See `docs/FEATURES.md` for the rows.
