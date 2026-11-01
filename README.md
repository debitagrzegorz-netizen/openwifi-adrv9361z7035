# openwifi on ADRV9361-Z7035

Software sources and scripts for the open-sdr/openwifi port to the Analog
Devices ADRV9361-Z7035 SOM on the ADRV1CRR-BOB carrier, built with AMD
PetaLinux 2025.1.

Status: the Linux image is built from a System Device Tree (SDT) project that
`build.sh` creates. This tree requires an XSA. The FPGA build is not yet
included. The v1.0 XSA SHA256 is
`b9a619acfff25ac07774c1afd51cc7eb1b071cb7273312407c4358c3fb525c3b`.
`hw/` only consumes that supplied XSA. The from-scratch FPGA track is paused.

## Quick build

```
cp config/local.conf.example config/local.conf
# fill in tool and cache paths
./build.sh all --xsa /path/to/system.xsa
```

`all` runs fetch, sdt, plnx-create, sw, and image. It does not flash and it
does not run the on-board tests. See `docs/BUILD.md`.

## Hardware

- SOM: ADRV9361-Z7035 (Zynq xc7z035, AD9361, 40 MSPS)
- Carrier: ADRV1CRR-BOB
- Antennas: SOM U.FL RX1A and TX1A (device-tree port select 0)

## License

See `LICENSE` and `LICENSES.md`. This tree is prepared for later publication.
It is not published from this repository.
