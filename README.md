# openwifi on ADRV9361-Z7035

Software sources and scripts for the open-sdr/openwifi port to the Analog
Devices ADRV9361-Z7035 SOM on the ADRV1CRR-BOB carrier, built with AMD
PetaLinux 2025.1.

Status: the Linux image is built from a System Device Tree (SDT) project that
`build.sh` creates. The FPGA flow is not in this tree yet. `hw/` only consumes
a supplied XSA. The v1.0 XSA is the hardware input. The from-scratch FPGA track
is paused.

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
