# Build

Requirements: Vivado, Vitis and PetaLinux 2025.1, the pinned git checkouts
named in `config/local.conf`, and shared `DL_DIR` / `SSTATE_DIR` if you do
not want a cold Yocto download.

```
cp config/local.conf.example config/local.conf
./build.sh all
```

`all` builds the FPGA first (`hw`) and then the software image. With
`--xsa <v1.0.xsa>` it skips `hw` and uses the supplied v1.0 XSA instead.

Stages, each idempotent and logged under `build/logs/<stage>.log`:

| Stage | Action |
|---|---|
| `hw` | `hw/build_hw.tcl`: the FPGA project, bitstream and XSA, with per-stage input hashes and the sub-IP equivalence check. |
| `fetch` | Check pinned revisions. Clone openwifi into `build/src/openwifi`. |
| `sdt` | `sw/sdt/gen_sdt.sh` runs `sdtgen` on the XSA. Fails if the XSA hash is neither v1.0 nor the one the `hw` stage recorded. |
| `plnx-create` | `petalinux-create --template zynq`, import the SDT, apply config, silentconfig, verify. |
| `sw` | `petalinux-build`, including the multiconfig FSBL. |
| `image` | `petalinux-package --boot`, WIC, gates, `SHA256SUMS`, `build-info.json`. |
| `gates` | Re-run the image gates without packaging. |
| `flash` | Requires `--device` and `--yes`. Refuses otherwise. |
| `test` | `tests/run_regression.sh --matrix`. |

`all` is hw + fetch + sdt + plnx-create + sw + image. It does not flash.

The Linux device tree is strategy B. See `docs/SDT-NOTES.md`.

Image gates:

1. Bitstream payload in `BOOT.BIN`, the FAT `system.bit`, and the XSA bitstream match.
2. `scripts/check_dtb_irqs.sh` on the final DTB.
3. Critical AD9361, IRQ, DMA, Ethernet, SD, UART, and USB nodes match the v1.0 reference, and `docs/SDT-NOTES.md` has reviewed the remaining diff.
4. `sdr.ko` vermagic matches the kernel release.
5. The rootfs contains the openwifi packages and the files `wgd.sh` needs, including `/etc/openwifi-build-info`.

## Pinned kernel and libiio

meta-adi builds the ADI kernel (`linux-xlnx`) and libiio with
`SRCREV = "${AUTOREV}"`. Without a pin, two builds a day apart can get
different kernels. The build is reproducible only with the pins in
`config/versions.conf`:

- `LINUX_ADI_REV`, the ADI Linux commit,
- `LIBIIO_REV`, the libiio commit.

`build.sh` writes both into the PetaLinux BSP configuration, and the
`meta-openwifi` bbappends apply them. Both values are recorded in
`build/images/build-info.json` and in `/etc/openwifi-build-info` on the
target.

To bump a pin on purpose:

1. Change the value in `config/versions.conf` and commit it on its own.
2. Run `./build.sh all` from a clean clone.
3. Check that `sdr.ko` vermagic matches the new kernel (image gate 4).
4. Run the full matrix (`docs/TESTING.md`) and the soak before you tag.
