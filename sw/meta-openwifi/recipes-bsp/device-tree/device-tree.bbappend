# SPDX-License-Identifier: GPL-2.0-only
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Linux DTB is the ADI kernel DTS (strategy B). SDT still supplies pl.dtsi.
DTB_PL_DELETE = "pl-delete-nodes-openwifi-adrv9361z7035-bob"

SRC_URI:append = " \
    file://system-user.dtsi \
    file://openwifi.dtsi \
    file://openwifi-adi-cleanup.dtsi \
    file://pl-delete-nodes-openwifi-adrv9361z7035-bob.dtsi \
"
