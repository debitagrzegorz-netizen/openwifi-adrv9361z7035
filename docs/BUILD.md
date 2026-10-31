# Build

Requirements: Vitis and PetaLinux 2025.1, the pinned git checkouts named in
`config/local.conf`, and shared `DL_DIR` / `SSTATE_DIR` if you do not want a
cold Yocto download.

```
cp config/local.conf.example config/local.conf
./build.sh all --xsa <v1.0.xsa>
```

Stages, each idempotent and logged under `build/logs/<stage>.log`:

| Stage | Action |
|---|---|
| `fetch` | Check pinned revisions. Clone openwifi into `build/src/openwifi`. |
| `sdt` | `sw/sdt/gen_sdt.sh` runs `sdtgen` on the XSA. Fails if the XSA hash is not v1.0. |
| `plnx-create` | `petalinux-create --template zynq`, import the SDT, apply config, silentconfig, verify. |
| `sw` | `petalinux-build`, including the multiconfig FSBL. |
| `image` | `petalinux-package --boot`, WIC, gates, `SHA256SUMS`, `build-info.json`. |
| `gates` | Re-run the image gates without packaging. |
| `flash` | Requires `--device` and `--yes`. Refuses otherwise. |
| `test` | `tests/run_regression.sh --matrix`. |

`all` is fetch + sdt + plnx-create + sw + image. It does not flash.

The Linux device tree is strategy B. See `docs/SDT-NOTES.md`.

Image gates:

1. Bitstream payload in `BOOT.BIN`, the FAT `system.bit`, and the XSA bitstream match.
2. `scripts/check_dtb_irqs.sh` on the final DTB.
3. Critical AD9361, IRQ, DMA, Ethernet, SD, UART, and USB nodes match the v1.0 reference, and `docs/SDT-NOTES.md` has reviewed the remaining diff.
4. `sdr.ko` vermagic matches the kernel release.
5. The rootfs contains the openwifi packages and the files `wgd.sh` needs, including `/etc/openwifi-build-info`.
