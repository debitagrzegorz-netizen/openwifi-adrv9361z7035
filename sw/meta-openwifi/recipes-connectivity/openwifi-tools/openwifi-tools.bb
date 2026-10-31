SUMMARY = "OpenWiFi sdrctl, inject_80211 and side_ch_ctl"
LICENSE = "AGPL-3.0-or-later & GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://../LICENSE;md5=73f1eb20517c55bf9493b7dd6e480788"

SRC_URI = "git://${OPENWIFI_REPO};protocol=file;branch=${OPENWIFI_BRANCH};destsuffix=git"
SRCREV = "${OPENWIFI_REV}"
S = "${WORKDIR}/git/user_space"

DEPENDS = "libnl libpcap"
RDEPENDS:${PN} = "libnl"

do_configure() {
    if [ ! -f ${S}/sdrctl_src/version.c ]; then
        echo 'const char sdrctl_version[] = "openwifi-adrv9361";' > ${S}/sdrctl_src/version.c
    fi
}

do_compile() {
    oe_runmake -C ${S}/sdrctl_src \
        CC="${CC}" \
        CFLAGS="${CFLAGS} -DCONFIG_LIBNL30 -I${STAGING_INCDIR}/libnl3" \
        LDFLAGS="${LDFLAGS}" \
        NO_PKG_CONFIG=1 \
        LIBS="-lnl-genl-3 -lnl-3" \
        NLLIBNAME=libnl-3.0
    ${CC} ${CFLAGS} ${LDFLAGS} -I${S}/inject_80211 -o inject_80211 \
        ${S}/inject_80211/inject_80211.c -lpcap
    ${CC} ${CFLAGS} ${LDFLAGS} -o side_ch_ctl \
        ${S}/side_ch_ctl_src/side_ch_ctl.c
}

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${S}/sdrctl_src/sdrctl ${D}${sbindir}/sdrctl
    install -m 0755 inject_80211 ${D}${sbindir}/inject_80211
    install -m 0755 side_ch_ctl ${D}${sbindir}/side_ch_ctl
}

FILES:${PN} = " \
    ${sbindir}/sdrctl \
    ${sbindir}/inject_80211 \
    ${sbindir}/side_ch_ctl \
"
