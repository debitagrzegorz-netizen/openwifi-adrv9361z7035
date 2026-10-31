#!/bin/sh
# Ensure hostname + DHCP on eth0 + restart avahi after link has an IPv4 address.
# Runs early (rcS S03) and may be re-run after multiuser start.

LOGTAG=openwifi-net
log() { echo "$LOGTAG: $*" ; }

echo openwifi > /etc/hostname 2>/dev/null || true
hostname openwifi 2>/dev/null || true

# Prefer eth0 (GEM); fall back to first non-lo / non-wifi interface
IFACE=eth0
if [ ! -d "/sys/class/net/$IFACE" ]; then
	for i in /sys/class/net/*; do
		n=$(basename "$i")
		case "$n" in
			lo|sit*|bonding*|dummy*|tun*|tap*|wlan*|sdr*|phy*) continue ;;
			*) IFACE=$n; break ;;
		esac
	done
fi

has_ipv4() {
	ip -4 addr show dev "$1" 2>/dev/null | grep -q 'inet '
}

if [ -d "/sys/class/net/$IFACE" ]; then
	ip link set "$IFACE" up 2>/dev/null || ifconfig "$IFACE" up 2>/dev/null || true

	if ! has_ipv4 "$IFACE"; then
		if command -v udhcpc >/dev/null 2>&1; then
			killall udhcpc 2>/dev/null || true
			# Foreground attempt first so address may exist before avahi restart
			udhcpc -i "$IFACE" -x hostname:openwifi -t 6 -T 2 -n \
				-s /usr/share/udhcpc/default.script 2>/dev/null || true
			if ! has_ipv4 "$IFACE"; then
				udhcpc -i "$IFACE" -x hostname:openwifi -t 10 -T 3 -A 5 -b \
					-s /usr/share/udhcpc/default.script 2>/dev/null || true
			fi
		fi
		ifup "$IFACE" 2>/dev/null || true
	fi

	# Wait briefly for DHCP (avahi needs a real address to publish)
	i=0
	while [ "$i" -lt 15 ]; do
		has_ipv4 "$IFACE" && break
		sleep 1
		i=$((i + 1))
	done

	if has_ipv4 "$IFACE"; then
		log "$IFACE has IPv4: $(ip -4 -o addr show dev "$IFACE" | awk '{print $4}')"
	else
		log "WARNING: $IFACE still has no IPv4 after wait"
	fi
else
	log "WARNING: no suitable network interface found"
fi

# Refresh mDNS after address may have appeared
restart_avahi() {
	if [ -x /etc/init.d/avahi-daemon ]; then
		/etc/init.d/avahi-daemon stop 2>/dev/null || true
		sleep 1
		/etc/init.d/avahi-daemon start 2>/dev/null || true
		return 0
	fi
	if command -v avahi-daemon >/dev/null 2>&1; then
		killall avahi-daemon 2>/dev/null || true
		sleep 1
		avahi-daemon -D 2>/dev/null || true
	fi
}

restart_avahi
# Delayed mDNS refresh (DHCP late arrival / dbus race)
if [ -x /usr/sbin/openwifi-mdns-refresh.sh ]; then
  ( sleep 3; /usr/sbin/openwifi-mdns-refresh.sh ) >/dev/null 2>&1 &
  ( sleep 15; /usr/sbin/openwifi-mdns-refresh.sh ) >/dev/null 2>&1 &
else
  ( sleep 5; restart_avahi ) >/dev/null 2>&1 &
fi

exit 0
