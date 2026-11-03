# SPDX-License-Identifier: GPL-2.0-only
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://openwifi.cfg \
    file://0001-ad9361-export-openwifi-helpers.patch \
"

# U-Boot boots image.ub. CONFIG_DTFILE names the SDT domain tree, so the
# fitImage default has to be selected here or Linux boots cortexa9-linux.dtb.
FIT_CONF_DEFAULT_DTB = "system-top.dtb"

# kernel-fitimage copies every dtb in the device-tree sysroot into image.ub
# after the KERNEL_DEVICETREE loop. Keep the board tree and system-top.
# cortexa9-linux.dts stays in the kernel source and is not the FIT default.
fitimage_keep_board_dtb() {
    dtbdir="${EXTERNAL_KERNEL_DEVICETREE}"
    if [ -z "$dtbdir" ] || [ ! -d "$dtbdir" ]; then
        return 0
    fi
    find "$dtbdir" \( -name '*.dtb' -o -name '*.dtbo' \) \
        ! -name 'zynq-adrv9361-z7035-bob.dtb' \
        ! -name 'system-top.dtb' \
        -delete
}

do_assemble_fitimage:prepend() {
    fitimage_keep_board_dtb
}

do_assemble_fitimage_initramfs:prepend() {
    fitimage_keep_board_dtb
}

# meta-adi builds ADI's linux main with AUTOREV, so the kernel changed from one
# build to the next. Pin the revision from config/versions.conf (build.sh
# writes LINUX_ADI_REV into petalinuxbsp.conf).
SRCREV = "${LINUX_ADI_REV}"
SRCREV_machine = "${LINUX_ADI_REV}"
