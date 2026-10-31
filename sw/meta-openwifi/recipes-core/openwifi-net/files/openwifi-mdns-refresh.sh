#!/bin/sh
# Keep openwifi.local published after DHCP renewals / late eth0 address.
# Safe to run repeatedly from init or cron-like delayed shells.

LOGTAG=openwifi-mdns
log() { echo "$LOGTAG: $*" ; }

echo openwifi > /etc/hostname 2>/dev/null || true
hostname openwifi 2>/dev/null || true

# Ensure /etc/hosts has a stable hostname line for local resolution
if [ -f /etc/hosts ]; then
  if ! grep -qE '[[:space:]]openwifi(\.local)?([[:space:]]|$)' /etc/hosts 2>/dev/null; then
    echo "127.0.1.1	openwifi openwifi.local" >> /etc/hosts 2>/dev/null || true
  fi
fi

IFACE=eth0
if [ ! -d "/sys/class/net/$IFACE" ]; then
  for i in /sys/class/net/*; do
    n=$(basename "$i")
    case "$n" in
      lo|sit*|wlan*|sdr*|phy*) continue ;;
      *) IFACE=$n; break ;;
    esac
  done
fi

has_ipv4() {
  ip -4 addr show dev "$1" 2>/dev/null | grep -q 'inet '
}

if [ -d "/sys/class/net/$IFACE" ]; then
  ip link set "$IFACE" up 2>/dev/null || true
  if ! has_ipv4 "$IFACE" && command -v udhcpc >/dev/null 2>&1; then
    udhcpc -i "$IFACE" -x hostname:openwifi -t 5 -T 2 -n \
      -s /usr/share/udhcpc/default.script 2>/dev/null || true
  fi
fi

# Restart avahi only if we have IPv4 (publishing without address is useless)
if has_ipv4 "$IFACE"; then
  ADDR=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -1)
  log "refresh on $IFACE ($ADDR)"
  if [ -x /etc/init.d/avahi-daemon ]; then
    /etc/init.d/avahi-daemon restart 2>/dev/null \
      || { /etc/init.d/avahi-daemon stop 2>/dev/null; sleep 1; /etc/init.d/avahi-daemon start 2>/dev/null; }
  elif command -v avahi-daemon >/dev/null 2>&1; then
    killall avahi-daemon 2>/dev/null || true
    sleep 1
    avahi-daemon -D 2>/dev/null || true
  fi
  # Explicit workstation publish helps some clients
  if command -v avahi-publish-address >/dev/null 2>&1; then
    killall avahi-publish-address 2>/dev/null || true
    IPV4=$(echo "$ADDR" | cut -d/ -f1)
    if [ -n "$IPV4" ]; then
      avahi-publish-address -R openwifi.local "$IPV4" >/dev/null 2>&1 &
    fi
  fi
else
  log "skip: no IPv4 on $IFACE yet"
fi

exit 0
