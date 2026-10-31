# SPDX-License-Identifier: GPL-2.0-only
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://openwifi.cfg \
    file://0001-ad9361-export-openwifi-helpers.patch \
"
