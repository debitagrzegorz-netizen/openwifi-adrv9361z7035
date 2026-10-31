# SPDX-License-Identifier: GPL-2.0-only
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://openwifi.cfg \
    file://0001-ad9361-export-openwifi-helpers.patch \
"

# U-Boot boots image.ub. CONFIG_DTFILE names the SDT domain tree, so the
# fitImage default has to be selected here or Linux boots cortexa9-linux.dtb.
FIT_CONF_DEFAULT_DTB = "system-top.dtb"
