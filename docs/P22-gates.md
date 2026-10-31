# P22 SDT image gates

The Linux boot tree is strategy B. PetaLinux 2025.1 SDT supplies the machine
configuration, the FSBL, U-Boot, and `pl.dtsi`. The Linux DTB stays the ADI
kernel DTS `zynq-adrv9361-z7035-bob`, with the OpenWiFi overlay appended only
to `system-top.dts`. `image.ub` defaults to configuration `conf-system-top.dtb`.
The FAT `system.dtb` is that same tree. `cortexa9-linux.dtb` remains in the
FIT and is not the default.

## Clean-room stage times

One uninterrupted `./build.sh all` from a fresh clone, with only
`config/local.conf` added:

| Stage | Seconds | Result |
|---|---:|---|
| fetch | 0 | pass |
| sdt | 9 | pass |
| plnx-create | 33 | pass |
| sw | 552 | pass |
| image | 486 | pass |

An earlier clone failed in `image` because Bitbake reused a parse-cache hash
from before `BOOT.BIN` existed. `do_rootfs[file-checksums]` on `BOOT.BIN` and
`system.bit` fixed that. The times above are the repeat from an empty directory.

## Gates

The bitstream payload in `BOOT.BIN`, the FAT `system.bit`, and the input XSA
are the same: `d2a8a4bcc9d4be6049983b27bd3ac7ce1113a8e2c4eb3e09bef0110ae4d98cd0`,
13321404 bytes. `check_dtb_irqs.sh` passed. The semantic diff against
`sw/reference/v1.0-system.dts` is the empty `pl-bus` node plus phandle
renumbering, recorded in `SDT-NOTES.md`. AD9361 port selects are 0. SDR
interrupts are 29/30/33/34, DMA interrupts are 35/36 and 31/32, and I2C is 58.
Module vermagic matches the kernel in this image:
`6.12.0adi-v2025.1-27765-g7656316058fb`. The rootfs manifest contains the
OpenWiFi packages and the author scripts.

WIC SHA256 `cfc31b392567442f8c57e2eb1df0a6b731a00e5ea8d29c6f04e1ef485caa89ef`.
`BOOT.BIN` `f16ec69fa6d576ef700c9476e6e05039b62a271764b9b5712f61f32044e84665`.
`system.bit` `d25404eefb32db1dbc7aae4c5737aafdadb9142347b1493a053618fc9cdb910a`.
`system.dtb` `b0fbcc7b99be84cddad7d72575b763358c0a3842604db83b6567a6a67df60f06`.

The FIT also carries other ADI board DTBs compiled from the kernel tree. They
are not the default configuration.
