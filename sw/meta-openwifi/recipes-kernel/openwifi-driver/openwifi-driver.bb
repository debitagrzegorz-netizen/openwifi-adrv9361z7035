SUMMARY = "OpenWiFi mac80211 SoftMAC driver"
LICENSE = "AGPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://../LICENSE;md5=73f1eb20517c55bf9493b7dd6e480788"

inherit module

SRC_URI = "git://${OPENWIFI_REPO};protocol=file;branch=${OPENWIFI_BRANCH};destsuffix=git"
SRCREV = "${OPENWIFI_REV}"
S = "${WORKDIR}/git/driver"

EXTRA_OEMAKE += "KDIR=${STAGING_KERNEL_DIR}"

do_configure:append() {
    rev=$(printf '%s' "${SRCREV}" | cut -c1-8)
    printf '#define GIT_REV 0x%s\n' "$(printf '%s' "$rev" | tr 'a-f' 'A-F')" > ${S}/git_rev.h
    # pre_def.h is gitignored. make_all.sh writes this one define and nothing else.
    printf '%s\n' '#define USE_NEW_RX_INTERRUPT 1' > ${S}/pre_def.h
}

do_compile() {
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -C ${STAGING_KERNEL_DIR} M=${S} \
        ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
        CC="${KERNEL_CC}" LD="${KERNEL_LD}" AR="${KERNEL_AR}" \
        O=${STAGING_KERNEL_BUILDDIR} modules
}

do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra
    for f in $(find ${S} -name '*.ko'); do
        install -m 0644 "$f" ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/
    done
}

RPROVIDES:${PN} += "kernel-module-sdr kernel-module-side-ch"
FILES:${PN} += "${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra"
