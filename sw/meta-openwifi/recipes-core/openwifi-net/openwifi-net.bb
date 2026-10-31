SUMMARY = "OpenWiFi hostname, Avahi refresh and serial console helpers"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://hostname \
    file://openwifi-console.sh \
    file://openwifi-net-up.sh \
    file://openwifi-mdns-refresh.sh \
    file://openwifi-console.init \
    file://openwifi-net.init \
"

S = "${WORKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "openwifi-console"
INITSCRIPT_PARAMS = "start 02 S ."

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/hostname ${D}${sysconfdir}/hostname

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/openwifi-console.init ${D}${sysconfdir}/init.d/openwifi-console
    install -m 0755 ${WORKDIR}/openwifi-net.init ${D}${sysconfdir}/init.d/openwifi-net

    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/openwifi-console.sh ${D}${sbindir}/openwifi-console.sh
    install -m 0755 ${WORKDIR}/openwifi-net-up.sh ${D}${sbindir}/openwifi-net-up.sh
    install -m 0755 ${WORKDIR}/openwifi-mdns-refresh.sh ${D}${sbindir}/openwifi-mdns-refresh.sh

    install -d ${D}${sysconfdir}/rcS.d
    ln -sf ../init.d/openwifi-net ${D}${sysconfdir}/rcS.d/S03openwifi-net
    # Late refresh after avahi (S21) so openwifi.local is re-published with DHCP IP
    install -d ${D}${sysconfdir}/rc5.d ${D}${sysconfdir}/rc2.d ${D}${sysconfdir}/rc3.d ${D}${sysconfdir}/rc4.d
    for d in rc2.d rc3.d rc4.d rc5.d; do
        ln -sf ../init.d/openwifi-net ${D}${sysconfdir}/$d/S99openwifi-net
    done

    # Extra delayed mDNS refresh (survives late DHCP)
    cat > ${D}${sysconfdir}/init.d/openwifi-mdns << 'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          openwifi-mdns
# Required-Start:    $network $remote_fs
# Default-Start:     2 3 4 5
# Short-Description: Refresh openwifi.local mDNS publish
### END INIT INFO
case "$1" in
  start|restart|reload)
    /usr/sbin/openwifi-mdns-refresh.sh
    # Second attempt after DHCP may complete
    ( sleep 12; /usr/sbin/openwifi-mdns-refresh.sh ) >/dev/null 2>&1 &
    ;;
  stop) ;;
  *) echo "Usage: $0 {start|stop|restart}"; exit 1 ;;
esac
exit 0
EOF
    chmod 0755 ${D}${sysconfdir}/init.d/openwifi-mdns
    for d in rc2.d rc3.d rc4.d rc5.d; do
        ln -sf ../init.d/openwifi-mdns ${D}${sysconfdir}/$d/S98openwifi-mdns
    done
}

pkg_postinst_ontarget:${PN}() {
#!/bin/sh
if [ -f /etc/inittab ]; then
    if grep -q 'ttyPS0' /etc/inittab; then
        sed -i 's|^.*ttyPS0.*|PS0:12345:respawn:/sbin/getty -L 115200 ttyPS0 vt102|' /etc/inittab
    else
        echo 'PS0:12345:respawn:/sbin/getty -L 115200 ttyPS0 vt102' >> /etc/inittab
    fi
fi
hostname openwifi 2>/dev/null || true
echo openwifi > /etc/hostname
if [ -f /etc/hosts ] && ! grep -qE '[[:space:]]openwifi(\.local)?([[:space:]]|$)' /etc/hosts; then
    echo "127.0.1.1	openwifi openwifi.local" >> /etc/hosts
fi
}

FILES:${PN} = " \
    ${sysconfdir}/hostname \
    ${sysconfdir}/init.d/openwifi-console \
    ${sysconfdir}/init.d/openwifi-net \
    ${sysconfdir}/init.d/openwifi-mdns \
    ${sysconfdir}/rcS.d/S03openwifi-net \
    ${sysconfdir}/rc2.d/S99openwifi-net \
    ${sysconfdir}/rc3.d/S99openwifi-net \
    ${sysconfdir}/rc4.d/S99openwifi-net \
    ${sysconfdir}/rc5.d/S99openwifi-net \
    ${sysconfdir}/rc2.d/S98openwifi-mdns \
    ${sysconfdir}/rc3.d/S98openwifi-mdns \
    ${sysconfdir}/rc4.d/S98openwifi-mdns \
    ${sysconfdir}/rc5.d/S98openwifi-mdns \
    ${sbindir}/openwifi-console.sh \
    ${sbindir}/openwifi-net-up.sh \
    ${sbindir}/openwifi-mdns-refresh.sh \
"
