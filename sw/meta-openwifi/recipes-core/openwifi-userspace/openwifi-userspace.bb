SUMMARY = "OpenWiFi author userspace scripts and FIR files"
LICENSE = "AGPL-3.0-or-later"
# S is the openwifi repository root, so LICENSE is inside S.
LIC_FILES_CHKSUM = "file://LICENSE;md5=73f1eb20517c55bf9493b7dd6e480788"

SRC_URI = " \
    git://${OPENWIFI_REPO};protocol=file;branch=${OPENWIFI_BRANCH};destsuffix=git \
    file://wgd.sh.patch \
    file://wgd-print-identity.patch \
    file://load_fpga_img.sh.patch \
    file://slice_cfg.sh.patch \
    file://sdr-ad-hoc-iw.patch \
    file://openwifi.conf \
    file://70-openwifi-sdr0.rules \
    file://hostapd-openwifi-2g.conf \
    file://dnsmasq-sdr0.conf \
"
SRCREV = "${OPENWIFI_REV}"
# Patches are against the openwifi repository root (a/user_space/...).
S = "${WORKDIR}/git"

RDEPENDS:${PN} = "bash"

do_install() {
    install -d ${D}/home/analog/openwifi
    cp -a --no-preserve=ownership ${S}/user_space/. ${D}/home/analog/openwifi/
    chown -R root:root ${D}/home/analog/openwifi
    find ${D}/home/analog/openwifi -name '*.ko' -delete

    install -m 0644 ${WORKDIR}/hostapd-openwifi-2g.conf \
        ${D}/home/analog/openwifi/hostapd-openwifi-2g.conf
    install -m 0644 ${WORKDIR}/dnsmasq-sdr0.conf \
        ${D}/home/analog/openwifi/dnsmasq-sdr0.conf

    install -d ${D}${sysconfdir}/modprobe.d
    install -m 0644 ${WORKDIR}/openwifi.conf ${D}${sysconfdir}/modprobe.d/openwifi.conf

    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/70-openwifi-sdr0.rules \
        ${D}${sysconfdir}/udev/rules.d/70-openwifi-sdr0.rules
}

FILES:${PN} = " \
    /home/analog/openwifi \
    ${sysconfdir}/modprobe.d/openwifi.conf \
    ${sysconfdir}/udev/rules.d/70-openwifi-sdr0.rules \
"

pkg_postinst_ontarget:${PN}() {
#!/bin/sh
chown -R analog:analog /home/analog/openwifi 2>/dev/null || true
}
