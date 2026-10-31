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

# SDT installs pl.dtsi via sdt-artifacts. It does not create ${DT_FILES_PATH}/pl.dtsi.
# meta-adi appends the delete include onto that path, so the real file must
# already be there. Otherwise the include is the whole file, it is pulled in
# before the root node, and dtc rejects /delete-node/.
do_configure:prepend() {
    sdt_pl="${RECIPE_SYSROOT}/usr/share/sdt/${MACHINE}/pl.dtsi"
    if [ ! -f "$sdt_pl" ]; then
        sdt_pl=$(echo ${RECIPE_SYSROOT}/usr/share/sdt/*/pl.dtsi)
    fi
    if [ ! -f "$sdt_pl" ]; then
        bbfatal "SDT pl.dtsi is not in the sdt-artifacts sysroot"
    fi
    mkdir -p "${DT_FILES_PATH}"
    cp -f "$sdt_pl" "${DT_FILES_PATH}/pl.dtsi"
}
