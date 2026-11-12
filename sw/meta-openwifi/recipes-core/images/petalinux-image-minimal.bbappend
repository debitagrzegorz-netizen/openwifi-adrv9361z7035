# cfg80211 expects regulatory.db, which is provided by wireless-regdb-static.
IMAGE_INSTALL:append = " openwifi-userspace openwifi-driver openwifi-tools hostapd iw wireless-regdb-static"
# tcpdump is in meta-networking. dnsmasq is the DHCP server: the 2025.1 layers
# ship dhcp-relay, not an ISC dhcp-server, and no wireless-tools recipe.
# dnsmasq is not started at boot (see openwifi_p01_runtime).
IMAGE_INSTALL:append = " tcpdump dnsmasq iperf3"
IMAGE_INSTALL:append = " avahi-daemon avahi-utils"
# xilinx_dma as module (CONFIG_XILINX_DMA=m) — must load after AD9361 clocks
IMAGE_INSTALL:append = " kernel-module-xilinx-dma"
# hostname, eth0 DHCP, avahi, ttyPS0 getty helpers
IMAGE_INSTALL:append = " openwifi-net"
# OpenWiFi userspace control + libnl for sdrctl
IMAGE_INSTALL:append = " libnl wpa-supplicant"
IMAGE_INSTALL:append = " u-boot-xlnx-env"
IMAGE_FSTYPES:append = " wic wic.xz wic.bmap"

ROOTFS_POSTPROCESS_COMMAND:append = " openwifi_boot_extras; openwifi_rootfs_console_net;"

openwifi_rootfs_boot_cleanup() {
	# This board has no battery-backed RTC and does not run an NFS server.
	# Drop the boot-time hooks so init does not emit avoidable warnings.
	rm -f ${IMAGE_ROOTFS}/etc/rcS.d/S40hwclock.sh \
		${IMAGE_ROOTFS}/etc/rcS.d/S*save-rtc.sh \
		${IMAGE_ROOTFS}/etc/rc2.d/S12rpcbind \
		${IMAGE_ROOTFS}/etc/rc2.d/S15mountnfs.sh \
		${IMAGE_ROOTFS}/etc/rc2.d/S19nfscommon \
		${IMAGE_ROOTFS}/etc/rc2.d/S20nfsserver \
		${IMAGE_ROOTFS}/etc/rc3.d/S12rpcbind \
		${IMAGE_ROOTFS}/etc/rc3.d/S15mountnfs.sh \
		${IMAGE_ROOTFS}/etc/rc3.d/S19nfscommon \
		${IMAGE_ROOTFS}/etc/rc3.d/S20nfsserver \
		${IMAGE_ROOTFS}/etc/rc4.d/S12rpcbind \
		${IMAGE_ROOTFS}/etc/rc4.d/S15mountnfs.sh \
		${IMAGE_ROOTFS}/etc/rc4.d/S19nfscommon \
		${IMAGE_ROOTFS}/etc/rc4.d/S20nfsserver \
		${IMAGE_ROOTFS}/etc/rc5.d/S12rpcbind \
		${IMAGE_ROOTFS}/etc/rc5.d/S15mountnfs.sh \
		${IMAGE_ROOTFS}/etc/rc5.d/S19nfscommon \
		${IMAGE_ROOTFS}/etc/rc5.d/S20nfsserver 2>/dev/null || true
	# /etc/init.d/bootmisc.sh calls hwclock.sh directly if it is executable.
	# Disable execute bit so test -x fails on RTC-less targets.
	if [ -f ${IMAGE_ROOTFS}/etc/init.d/hwclock.sh ]; then
		chmod 0644 ${IMAGE_ROOTFS}/etc/init.d/hwclock.sh
	fi
	# Also disable hwclock access through initscript defaults to avoid
	# /dev/misc/rtc probes even if scripts are restored by another package.
	if [ -f ${IMAGE_ROOTFS}/etc/default/rcS ]; then
		grep -q '^HWCLOCKACCESS=' ${IMAGE_ROOTFS}/etc/default/rcS \
			&& sed -i 's/^HWCLOCKACCESS=.*/HWCLOCKACCESS=no/' ${IMAGE_ROOTFS}/etc/default/rcS \
			|| echo 'HWCLOCKACCESS=no' >> ${IMAGE_ROOTFS}/etc/default/rcS
	fi
}

ROOTFS_POSTPROCESS_COMMAND:append = " openwifi_rootfs_boot_cleanup;"

openwifi_rootfs_console_net() {
	# Hostname
	echo openwifi > ${IMAGE_ROOTFS}/etc/hostname

	# Direct getty -L on UART1 (interactive RX+TX); avoid start_getty matching quirks
	if [ -f ${IMAGE_ROOTFS}/etc/inittab ]; then
		if grep -q 'ttyPS0' ${IMAGE_ROOTFS}/etc/inittab; then
			sed -i 's|^.*ttyPS0.*|PS0:12345:respawn:/sbin/getty -L 115200 ttyPS0 vt102|' ${IMAGE_ROOTFS}/etc/inittab
		else
			echo 'PS0:12345:respawn:/sbin/getty -L 115200 ttyPS0 vt102' >> ${IMAGE_ROOTFS}/etc/inittab
		fi
	fi

	# Ethernet only at boot — do NOT auto-ifup wlan0/sdr0 (triggers openwifi_start + IRQs)
	install -d ${IMAGE_ROOTFS}/etc/network
	cat > ${IMAGE_ROOTFS}/etc/network/interfaces << 'EOF'
# OpenWiFi ADRV9361-Z7035 — net.ifnames=0 keeps eth0
# wlan0/sdr0: bring up only after ./load_openwifi.sh (manual ifup / hostapd)
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
	hostname openwifi
	udhcpc_opts -t 10 -T 3 -A 5 -b

allow-hotplug eth1
iface eth1 inet dhcp
	hostname openwifi

# SoftMAC — manual only (avoid RCU stall from early IRQ enable)
# P01: autonet ifup disabled
#iface wlan0 inet manual
#iface sdr0 inet manual
EOF

	# Do not start hostapd at boot (default conf uses interface=wlan0 → openwifi_start)
	rm -f ${IMAGE_ROOTFS}/etc/rcS.d/S*hostapd \
		${IMAGE_ROOTFS}/etc/rc2.d/S*hostapd \
		${IMAGE_ROOTFS}/etc/rc3.d/S*hostapd \
		${IMAGE_ROOTFS}/etc/rc4.d/S*hostapd \
		${IMAGE_ROOTFS}/etc/rc5.d/S*hostapd 2>/dev/null || true
	# Neutralize default hostapd.conf so accidental start does not open wlan0
	if [ -f ${IMAGE_ROOTFS}/etc/hostapd.conf ]; then
		sed -i 's|^interface=wlan0|#interface=wlan0  # use /home/analog/hostapd-openwifi.conf|' \
			${IMAGE_ROOTFS}/etc/hostapd.conf || true
	fi

	# Never auto-load SoftMAC at boot
	rm -f ${IMAGE_ROOTFS}/etc/modules-load.d/sdr.conf 2>/dev/null || true
	if [ -f ${IMAGE_ROOTFS}/etc/modules ]; then
		sed -i '/^sdr$/d' ${IMAGE_ROOTFS}/etc/modules || true
	fi
}

openwifi_boot_extras() {
	B=${IMAGE_ROOTFS}/boot
	install -d "$B"

	# Single BOOT.BIN only (FAT is case-insensitive)
	if [ -f ${DEPLOY_DIR_IMAGE}/BOOT.BIN ]; then
		install -m 0644 ${DEPLOY_DIR_IMAGE}/BOOT.BIN "$B/BOOT.BIN"
	elif [ -f ${DEPLOY_DIR_IMAGE}/boot.bin ]; then
		install -m 0644 ${DEPLOY_DIR_IMAGE}/boot.bin "$B/BOOT.BIN"
	fi
	rm -f "$B"/BOOT.bin "$B"/boot.bin "$B"/Boot.bin

	for f in image.ub system.bit boot.scr system.dtb; do
		if [ -f ${DEPLOY_DIR_IMAGE}/$f ]; then
			install -m 0644 ${DEPLOY_DIR_IMAGE}/$f "$B/$f"
		fi
	done
	# PetaLinux leaves the bitstream in images/linux/system.bit. The FAT
	# copy is what the boot guard hashes. Deploy does not always have it.
	if [ ! -f "$B/system.bit" ] && [ -f ${TOPDIR}/../images/linux/system.bit ]; then
		install -m 0644 ${TOPDIR}/../images/linux/system.bit "$B/system.bit"
	fi

	# Materialize symlinks (mcopy -s cannot put host symlinks on FAT)
	if [ -L "$B/uImage" ]; then
		cp -fL "$B/uImage" "$B/uImage.bin" 2>/dev/null || true
		rm -f "$B/uImage"
		[ -f "$B/uImage.bin" ] && mv "$B/uImage.bin" "$B/uImage"
	fi
	if [ -L "$B/zImage" ]; then
		cp -fL "$B/zImage" "$B/zImage.bin" 2>/dev/null || true
		rm -f "$B/zImage"
		[ -f "$B/zImage.bin" ] && mv "$B/zImage.bin" "$B/zImage"
	fi

	# Drop versioned long names and extra U-Boot scr artifacts
	rm -f "$B"/uImage-* "$B"/zImage-* "$B"/u-boot-xlnx-scr--*.scr 2>/dev/null || true

	# Optional dirs not needed on SD boot partition
	rm -rf "$B/pxeboot" "$B/pxelinux.cfg" "$B/devicetree" 2>/dev/null || true

	# Final safety: only one boot binary case
	ls -la "$B" || true
}

ROOTFS_POSTPROCESS_COMMAND:append = " openwifi_p01_runtime;"

openwifi_p01_runtime() {
	# debugfs: ad9361 loopback and direct_reg_access. wgd.sh also mounts it.
	if ! grep -q '[[:space:]]/sys/kernel/debug[[:space:]]' ${IMAGE_ROOTFS}/etc/fstab; then
		printf '%s\n' 'debugfs /sys/kernel/debug debugfs defaults 0 0' >> ${IMAGE_ROOTFS}/etc/fstab
	fi

	# dnsmasq must not start at boot. The stock config does not serve DHCP,
	# but a listener on every interface is not wanted on the lab eth0.
	rm -f ${IMAGE_ROOTFS}/etc/rcS.d/*dnsmasq \
		${IMAGE_ROOTFS}/etc/rc2.d/*dnsmasq \
		${IMAGE_ROOTFS}/etc/rc3.d/*dnsmasq \
		${IMAGE_ROOTFS}/etc/rc4.d/*dnsmasq \
		${IMAGE_ROOTFS}/etc/rc5.d/*dnsmasq 2>/dev/null || true

	# wgd.sh insmods ./<module>.ko from /home/analog/openwifi. Point those
	# names at the image modules, including the fixed side_ch.ko.
	# side_ch stays blacklisted so the OF modalias does not load it at boot.
	dest=${IMAGE_ROOTFS}/home/analog/openwifi
	install -d "$dest"
	ko=$(find ${IMAGE_ROOTFS}/lib/modules -name sdr.ko -print -quit || true)
	if [ -n "$ko" ]; then
		extra=$(dirname "$ko")
		kver=$(basename "$(dirname "$extra")")
		for m in sdr tx_intf rx_intf openofdm_tx openofdm_rx xpu side_ch; do
			if [ -f "$extra/$m.ko" ]; then
				ln -sfn "/lib/modules/$kver/extra/$m.ko" "$dest/$m.ko"
			fi
		done
	fi
	# The author tree ships inject_80211/ as sources. The image binary is
	# openwifi-tools in ${sbindir}. Replace that directory with a symlink.
	for t in sdrctl inject_80211 side_ch_ctl; do
		if [ -d "$dest/$t" ]; then
			rm -rf "$dest/$t"
		fi
		if [ -e ${IMAGE_ROOTFS}${sbindir}/$t ]; then
			ln -sfn "${sbindir}/$t" "$dest/$t"
		fi
	done
	# ${OPENWIFI_BOOT_SHA} is unused at runtime. do_rootfs is a Python task,
	# so this shell reference does not change its hash. The vardep below does.
	echo "openwifi boot sha ${OPENWIFI_BOOT_SHA}" >/dev/null
}

openwifi_write_build_info() {
	info=${IMAGE_ROOTFS}/etc/openwifi-build-info
	install -d ${IMAGE_ROOTFS}/etc
	bit=""
	for c in ${DEPLOY_DIR_IMAGE}/system.bit ${TOPDIR}/../images/linux/system.bit; do
		if [ -f "$c" ]; then
			bit=$(sha256sum "$c" | awk '{print $1}')
			break
		fi
	done
	cat > "$info" << EOF
openwifi_srcrev=${OPENWIFI_REV}
openwifi_hw_srcrev=${OPENWIFI_HW_REV}
adi_hdl_srcrev=${ADI_HDL_REV}
openofdm_rx_srcrev=${OPENOFDM_RX_REV}
meta_adi_srcrev=${META_ADI_REV}
linux_adi_srcrev=${LINUX_ADI_REV}
libiio_srcrev=${LIBIIO_REV}
pyadi_iio_srcrev=${PYADI_IIO_REV}
xsa_sha256=${OPENWIFI_XSA_SHA256}
bitstream_sha256=${bit}
tool_version=${OPENWIFI_TOOL_VERSION}
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}
ROOTFS_POSTPROCESS_COMMAND:append = " openwifi_write_build_info;"

# Hash of the packaged boot files. "missing" until the image stage packages them.
# The ${@} result is kept in the parse cache, so a later petalinux-build does
# not notice BOOT.BIN and system.bit appearing on disk. The file checksums are
# read when the task hash is built, which makes do_rootfs run again.
OPENWIFI_BOOT_SHA = "${@openwifi_boot_sha(d)}"
do_rootfs[vardeps] += "OPENWIFI_BOOT_SHA"
do_rootfs[file-checksums] += "${DEPLOY_DIR_IMAGE}/BOOT.BIN:True ${DEPLOY_DIR_IMAGE}/system.bit:True"

def openwifi_boot_sha(d):
    import hashlib
    import os
    digest = hashlib.sha256()
    deploy = d.getVar("DEPLOY_DIR_IMAGE") or ""
    for name in ("BOOT.BIN", "system.bit"):
        digest.update(name.encode())
        path = os.path.join(deploy, name)
        if os.path.isfile(path):
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(chunk)
        else:
            digest.update(b"missing")
    return digest.hexdigest()

