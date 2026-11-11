# openwifi on ADRV9361-Z7035

Sources and scripts for the open-sdr/openwifi port to the Analog Devices
ADRV9361-Z7035 SOM on the ADRV1CRR-BOB carrier, built with AMD Vivado and
PetaLinux 2025.1.

Status: v1.2 (`docs/RELEASE-v1.2.md`). v1.2 fixes the FPGA TX-queue freeze
in the hardware; the driver watchdog stays as a safety net. Previous release:
v1.1 (`docs/RELEASE-v1.1.md`). One command builds the FPGA and the
Linux image from sources. The Linux image is built from a System Device Tree
(SDT) project that `build.sh` creates. The v1.0 XSA
(`b9a619acfff25ac07774c1afd51cc7eb1b071cb7273312407c4358c3fb525c3b`) can
still be supplied with `--xsa`. Known issues are in `docs/KNOWN-ISSUES.md`.

The FIT image keeps two device trees. `system-top.dtb` is the default boot
configuration. `zynq-adrv9361-z7035-bob.dtb` is the in-kernel board tree that
`system-top` is assembled from. `cortexa9-linux.dts` stays in the kernel
source and is not copied into the FIT.

## Quick build

```
cp config/local.conf.example config/local.conf
# fill in tool and cache paths
./build.sh all
```

`all` runs hw, fetch, sdt, plnx-create, sw, and image (about 50 minutes). It
does not flash and it does not run the on-board tests. See `docs/BUILD.md`
and `docs/TESTING.md`.

## Hardware

- SOM: ADRV9361-Z7035 (Zynq xc7z035, AD9361, 40 MSPS)
- Carrier: ADRV1CRR-BOB
- Antennas: SOM U.FL RX1A and TX1A (device-tree port select 0)

## License

See `LICENSE` and `LICENSES.md`. This tree is prepared for later publication.
It is not published from this repository.
