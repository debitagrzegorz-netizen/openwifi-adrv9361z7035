FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " file://avahi-daemon.conf"

# Install a deterministic Avahi config instead of patching the generated file
# in place. The stock config on this image keeps IPv6 enabled and that adds an
# avoidable startup failure/race on the minimal SD build.
do_install:append() {
    install -d ${D}${sysconfdir}/avahi
    install -m 0644 ${WORKDIR}/avahi-daemon.conf ${D}${sysconfdir}/avahi/avahi-daemon.conf
}
