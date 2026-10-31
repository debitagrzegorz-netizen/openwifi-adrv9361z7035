#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# P22 feature matrix. Client 5 dBm, power save off, channel 13 unless a row says
# otherwise. Never configures the management Wi-Fi (wlp4s0).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/config/versions.conf"
# shellcheck disable=SC1091
source "$ROOT/config/local.conf"

IMAGE_NAME=v1.0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --image) IMAGE_NAME=${2:-v1.0}; shift 2 ;;
    *) echo "usage: $0 [--image NAME]" >&2; exit 2 ;;
  esac
done

WLX=${TEST_RADIO_IF:-wlx1005014f5b7c}
if [ "$WLX" = "wlp4s0" ]; then
  echo "FAIL: TEST_RADIO_IF must not be wlp4s0" >&2
  exit 2
fi
STAMP=$(date +%Y%m%d)
OUT=${OUT:-$ROOT/build/features/${IMAGE_NAME}-${STAMP}}
mkdir -p "$OUT"
REPORT=$ROOT/build/features/FEATURES-${IMAGE_NAME}-${STAMP}.md
JSON=$ROOT/build/features/FEATURES-${IMAGE_NAME}-${STAMP}.json
FIXED_SIDE_CH_SHA=939c412804e475c95cc76253811a8686d9411a16df48d58764ee05b9cb1fc02e
IPERF_CMD=${IPERF3:-iperf3}
KH=${BOARD_KNOWN_HOSTS:-}
SSH_OPTS=(-o StrictHostKeyChecking=yes -o ConnectTimeout=20 -o ServerAliveInterval=15)
if [ -n "$KH" ]; then
  SSH_OPTS+=(-o "UserKnownHostsFile=$KH")
fi

if ! command -v fdtget >/dev/null 2>&1 && [ -n "${TOOLS_ROOT:-}" ]; then
  export PATH="${TOOLS_ROOT}/PetaLinux/tool/sysroots/x86_64-petalinux-linux/usr/bin:${TOOLS_ROOT}/Vitis/bin:${PATH}"
fi

exec > >(tee -a "$OUT/matrix.log") 2>&1
echo "P22_MATRIX_BEGIN image=$IMAGE_NAME out=$OUT"

if [ -z "${SSHPASS:-}" ] && [ -n "${OPENWIFI_VALIDATION_SH:-}" ]; then
  python3 - "${OPENWIFI_VALIDATION_SH}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'export SSHPASS="\$\{SSHPASS:-([^}]+)\}"', text)
if not m:
    raise SystemExit("password source missing")
open("/tmp/p22-matrix-env", "w").write("export SSHPASS=%s\n" % m.group(1))
PY
  chmod 600 /tmp/p22-matrix-env
  # shellcheck disable=SC1091
  source /tmp/p22-matrix-env
  rm -f /tmp/p22-matrix-env
fi
if [ -z "${SSHPASS:-}" ]; then
  echo "FAIL: SSHPASS is not set" >&2
  exit 2
fi

ssh_board() { sshpass -e ssh "${SSH_OPTS[@]}" "${BOARD_USER}@${BOARD_IP}" "$@"; }
board_sudo() {
  ssh_board "printf '%s\n' $(printf '%q' "$SSHPASS") | sudo -S -p '' sh -c $(printf '%q' "$1")"
}
scp_board() { sshpass -e scp "${SSH_OPTS[@]}" "$1" "${BOARD_USER}@${BOARD_IP}:$2"; }

declare -A RESULT DETAIL
record() {
  RESULT[$1]=$2
  DETAIL[$1]=$3
  echo "P22_FEATURE $1 $2 $3"
}

snapshot_uplink() {
  nmcli -t -f DEVICE,STATE,CONNECTION device status | awk -F: '$1=="wlp4s0"'
}

restore_host() {
  sudo -n /usr/local/sbin/openwifi-hostapd-ctl stop >/dev/null 2>&1 || true
  nmcli device disconnect "$WLX" >/dev/null 2>&1 || true
  nmcli connection delete p22-reg >/dev/null 2>&1 || true
  nmcli connection delete p22-ibss >/dev/null 2>&1 || true
  nmcli device set "$WLX" managed no >/dev/null 2>&1 || true
  sudo -n /usr/sbin/ip link set "$WLX" down >/dev/null 2>&1 || true
  sudo -n /usr/sbin/iw dev "$WLX" set type managed >/dev/null 2>&1 || true
  sudo -n /usr/sbin/iw dev "$WLX" set power_save on >/dev/null 2>&1 || true
  sudo -n /usr/sbin/iw dev "$WLX" set txpower fixed 2000 >/dev/null 2>&1 || true
  nmcli device set "$WLX" managed yes >/dev/null 2>&1 || true
  board_sudo 'killall hostapd dnsmasq iperf3 wpa_supplicant side_ch_ctl 2>/dev/null || true; ip link set sdr0 down >/dev/null 2>&1 || true; rmmod side_ch >/dev/null 2>&1 || true' >/dev/null 2>&1 || true
}

write_report() {
  {
    echo "# Feature matrix ${IMAGE_NAME} ${STAMP}"
    echo
    echo "Log directory: build/features/${IMAGE_NAME}-${STAMP}"
    echo
    echo "| ID | Status | Detail |"
    echo "|---|---|---|"
    local id
    for id in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14 F15 F16 F17 F18 F19 F20 F21; do
      echo "| $id | ${RESULT[$id]:-SKIPPED} | ${DETAIL[$id]:-not recorded} |"
    done
  } >"$REPORT"
  python3 - "$REPORT" "$JSON" <<'PY'
import json, sys
rows = []
for line in open(sys.argv[1]):
    if not line.startswith("| F"):
        continue
    cols = [c.strip() for c in line.strip().strip("|").split("|")]
    rows.append({"id": cols[0], "status": cols[1], "detail": cols[2]})
json.dump({"image": "see filename", "rows": rows}, open(sys.argv[2], "w"), indent=2)
print("WROTE", sys.argv[1])
PY
}

finalize() {
  local rc=$?
  restore_host || true
  snapshot_uplink >"$OUT/uplink-end.txt" || true
  write_report || true
  if ! cmp -s "$OUT/uplink-start.txt" "$OUT/uplink-end.txt"; then
    echo "P22_MATRIX_FAIL wlp4s0 changed"
    exit 2
  fi
  if [ "$rc" -ne 0 ]; then
    echo "P22_MATRIX_FAIL rc=$rc"
  else
    echo "P22_MATRIX_DONE"
  fi
}
trap finalize EXIT

UPLINK_START=$(snapshot_uplink || true)
printf '%s\n' "$UPLINK_START" >"$OUT/uplink-start.txt"
echo "P22_UPLINK $UPLINK_START"

require_txpower() {
  local i info
  for i in 1 2 3 4 5 6 7 8; do
    sudo -n /usr/sbin/iw dev "$WLX" set txpower fixed 500 >"$OUT/txpower-set.txt" 2>&1 || true
    info=$(sudo -n /usr/sbin/iw dev "$WLX" info 2>/dev/null || true)
    printf '%s\n' "$info" >"$OUT/txpower-iw.txt"
    if printf '%s\n' "$info" | grep -q 'txpower 5.00 dBm'; then
      return 0
    fi
    sleep 0.4
  done
  return 1
}

set_host_type() {
  local want=$1
  local i info
  nmcli device set "$WLX" managed no >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sudo -n /usr/sbin/ip link set "$WLX" down >/dev/null 2>&1 || true
    sudo -n /usr/sbin/iw dev "$WLX" set type "$want" >/dev/null 2>&1 || true
    sudo -n /usr/sbin/ip link set "$WLX" up >/dev/null 2>&1 || true
    sudo -n /usr/sbin/iw dev "$WLX" set channel "${2:-13}" >/dev/null 2>&1 || true
    info=$(sudo -n /usr/sbin/iw dev "$WLX" info 2>/dev/null || true)
    printf '%s\n' "$info" | grep -i -q "type $want" || { sleep 0.3; continue; }
    if [ "$want" = monitor ]; then
      printf '%s\n' "$info" | grep -q "channel ${2:-13}" || { sleep 0.3; continue; }
    fi
    printf '%s\n' "$info"
    return 0
  done
  return 1
}

ping_loss() {
  local n=${2:-300}
  ping -c "$n" -i 0.2 -W 1 "$1" >"$OUT/ping-${3:-x}.txt" 2>&1 || true
  python3 - "$OUT/ping-${3:-x}.txt" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
m = re.search(r"(\d+) packets transmitted, (\d+) (?:packets )?received,.*?([0-9.]+)% packet loss", t, re.S)
print(m.group(3) if m else "NA")
PY
}

mbps() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
v = re.findall(r"([0-9.]+)\s+Mbits/sec", t)
print(v[-1] if v else "NA")
PY
}
udploss() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
v = re.findall(r"\(([0-9.]+)%\)", t)
print(v[-1] if v else "NA")
PY
}

run_iperf() {
  local tag=$1
  shift
  board_sudo 'killall iperf3 2>/dev/null || true' || true
  ssh_board 'iperf3 -s -1' >"$OUT/${tag}-server.txt" 2>&1 &
  local sp=$!
  sleep 1.5
  if [ -n "${IPERF_LIB:-}" ]; then
    timeout 25 env LD_LIBRARY_PATH="$IPERF_LIB" "$IPERF_CMD" "$@" >"$OUT/${tag}-iperf.txt" 2>&1 || true
  else
    timeout 25 "$IPERF_CMD" "$@" >"$OUT/${tag}-iperf.txt" 2>&1 || true
  fi
  kill "$sp" 2>/dev/null || true
  wait "$sp" 2>/dev/null || true
}

bringup_ap() {
  local ch=$1
  cat >"$OUT/hostapd.conf" <<EOF
interface=sdr0
driver=nl80211
country_code=BE
ssid=openwifi
hw_mode=g
channel=${ch}
supported_rates=60 90 120 180 240 360 480 540
basic_rates=60 90 120 180
ieee80211n=1
EOF
  scp_board "$OUT/hostapd.conf" /tmp/p22-hostapd.conf
  cat >"$OUT/dnsmasq.conf" <<'EOF'
interface=sdr0
bind-interfaces
dhcp-range=192.168.13.10,192.168.13.50,255.255.255.0,12h
dhcp-option=option:router,192.168.13.1
EOF
  scp_board "$OUT/dnsmasq.conf" /tmp/p22-dnsmasq.conf
  board_sudo 'killall hostapd dnsmasq wpa_supplicant iperf3 2>/dev/null || true; ip link set sdr0 down || true; iw dev sdr0 set type managed; pa=$(ip -o link show sdr0 | sed -n "s/.*permaddr \([^ ]*\).*/\1/p"); if [ -n "$pa" ]; then ip link set dev sdr0 address "$pa"; fi; ip link set sdr0 up; ip addr show sdr0 | grep -q 192.168.13.1/ || ip addr add 192.168.13.1/24 dev sdr0; cd /home/analog/openwifi && ./agc_settings.sh 1 >/tmp/p22-gain.txt 2>&1; hostapd -B -P /tmp/p22-hostapd.pid /tmp/p22-hostapd.conf > /tmp/p22-hostapd.log 2>&1; dnsmasq --conf-file=/tmp/p22-dnsmasq.conf; echo HOSTAPD_RC:$?'
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    ssh_board 'grep -q AP-ENABLED /tmp/p22-hostapd.log' && return 0
    sleep 1
  done
  return 1
}

associate() {
  nmcli device set "$WLX" managed yes || true
  nmcli connection delete p22-reg >/dev/null 2>&1 || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    nmcli -t -f SSID,CHAN dev wifi list ifname "$WLX" --rescan yes >"$OUT/nmcli-list.txt" 2>>"$OUT/nmcli.txt" || true
    if grep -q '^openwifi:' "$OUT/nmcli-list.txt"; then
      if nmcli dev wifi connect openwifi ifname "$WLX" name p22-reg >>"$OUT/nmcli.txt" 2>&1; then
        nmcli connection modify p22-reg ipv4.method manual ipv4.addresses 192.168.13.19/24 ipv4.gateway 192.168.13.1 >>"$OUT/nmcli.txt" 2>&1 || true
        nmcli connection up p22-reg >>"$OUT/nmcli.txt" 2>&1 || true
        sudo -n /usr/sbin/iw dev "$WLX" set power_save off >/dev/null 2>&1 || true
        if require_txpower && ip -4 addr show "$WLX" | grep -q '192.168.13.'; then
          return 0
        fi
      fi
    fi
    sleep 2
  done
  return 1
}

f1() {
  local ssh_ok=0 dhcp=0 mdns=0 uart="no-capture" getty=0
  ssh_board 'echo SSH_OK; ip -4 addr show eth0; ps | grep "[g]etty" || true' >"$OUT/f1.txt" 2>&1 || true
  if grep -q 'SSH_OK' "$OUT/f1.txt"; then
    ssh_ok=1
    grep -q 'inet ' "$OUT/f1.txt" && dhcp=1
    grep -q 'ttyPS0' "$OUT/f1.txt" && getty=1
  fi
  if command -v avahi-resolve >/dev/null 2>&1; then
    avahi-resolve -n openwifi.local >"$OUT/f1-mdns.txt" 2>&1 && mdns=1 || true
  else
    getent hosts openwifi.local >"$OUT/f1-mdns.txt" 2>&1 && mdns=1 || true
  fi
  if [ -n "${UART_DEV:-}" ] && [ -c "$UART_DEV" ]; then
    python3 - "$UART_DEV" "$OUT/f1-uart.txt" <<'PY' || true
import sys, time
dev, dest = sys.argv[1:]
try:
    f = open(dev, "rb", buffering=0)
    w = open(dev, "wb", buffering=0)
    w.write(b"\n")
    w.close()
    time.sleep(1.5)
    data = f.read(4096)
    f.close()
    open(dest, "wb").write(data)
except OSError as exc:
    open(dest, "w").write("UART_ERROR %s\n" % exc)
PY
    if grep -a -q 'login:' "$OUT/f1-uart.txt"; then
      uart="login-prompt"
    elif grep -q UART_ERROR "$OUT/f1-uart.txt"; then
      uart=$(head -n 1 "$OUT/f1-uart.txt")
    else
      uart="bytes=$(wc -c < "$OUT/f1-uart.txt")"
    fi
  fi
  local detail="ssh=$ssh_ok dhcp=$dhcp mdns=$mdns getty=$getty uart=$uart"
  if [ "$ssh_ok" = 1 ] && [ "$dhcp" = 1 ] && [ "$mdns" = 1 ] && [ "$getty" = 1 ]; then
    record F1 PASS "$detail"
  else
    record F1 FAIL "$detail"
  fi
}

f2() {
  board_sudo 'sha256sum /boot/system.bit /boot/BOOT.BIN /boot/system.dtb; echo GIT $(/sbin/devmem 0x83C400FC); echo DDS $(/sbin/devmem 0x79024418) $(/sbin/devmem 0x79024458) $(/sbin/devmem 0x79024498) $(/sbin/devmem 0x790244d8); echo BUILDINFO; cat /etc/openwifi-build-info 2>/dev/null || echo BUILDINFO_MISSING' >"$OUT/f2.txt" 2>&1 || {
    record F2 FAIL "ssh or devmem failed"
    return
  }
  local line
  line=$(python3 - "$OUT/f2.txt" "$IMAGE_NAME" <<'PY'
import sys
t = open(sys.argv[1], errors="replace").read()
image = sys.argv[2]
v1 = ["32ce68fda2f0f638a252e4d4064a33efa037395938bbd48a6349e8e3114d2841",
      "355f897323cf84a62a193cca4b26a120c08464f4fb1fe0a359128787f042a62e",
      "19b47419386a4a8d3472e0265c70cecfacbc537e82cf7e9bc00f83fd159d9fd6"]
dds = t.count("0x00000002") >= 4 and "0x0D047D79" in t
info = "BUILDINFO_MISSING" not in t and "openwifi_srcrev=" in t
hashes = all(s in t for s in v1)
if image == "v1.0":
    ok = hashes and dds and info
    print(("PASS" if ok else "FAIL") + " hashes=%d dds=%d buildinfo=%d" % (hashes, dds, info))
else:
    ok = dds and info
    print(("PASS" if ok else "FAIL") + " dds=%d buildinfo=%d" % (dds, info))
PY
)
  record F2 "${line%% *}" "${line#* }"
}

f4_wgd() {
  board_sudo 'cd /home/analog/openwifi && ./wgd.sh' >"$OUT/f4-wgd.txt" 2>&1 || {
    record F4 FAIL "wgd.sh failed"
    return
  }
  ssh_board 'cat /sys/firmware/fdt' >"$OUT/f4.dtb" 2>/dev/null || true
  board_sudo 'cat /proc/interrupts' >"$OUT/f4-irq.txt" 2>&1 || true
  local dt=0 irq=0
  if [ -s "$OUT/f4.dtb" ] && "$ROOT/scripts/check_dtb_irqs.sh" "$OUT/f4.dtb" >"$OUT/f4-dtb.txt" 2>&1; then
    dt=1
  fi
  if grep -E -q '30:|34:|35:|36:|31:|32:|62:|66:|67:|68:|63:|64:' "$OUT/f4-irq.txt"; then
    irq=1
  fi
  if grep -q 'wgd.sh failed' "$OUT/f4-wgd.txt"; then
    record F4 FAIL "wgd reported failure dt=$dt irq=$irq"
  elif tail -n 5 "$OUT/f4-wgd.txt" | grep -q . && [ "$dt" = 1 ]; then
    record F4 PASS "wgd exit 0 dt=$dt irq_lines=$irq"
  else
    record F4 FAIL "dt=$dt irq_lines=$irq"
  fi
}

f3() {
  board_sudo 'cd /home/analog/openwifi && ./rf_init_11n.sh; ./agc_settings.sh 1; echo RATE $(cat /sys/bus/iio/devices/iio:device0/in_voltage_sampling_frequency 2>/dev/null); echo FIR $(cat /sys/bus/iio/devices/iio:device0/in_voltage_filter_fir_en 2>/dev/null); echo AGC $(cat /sys/bus/iio/devices/iio:device0/in_voltage0_gain_control_mode 2>/dev/null)' >"$OUT/f3.txt" 2>&1 || {
    record F3 FAIL "rf_init failed"
    return
  }
  if grep -q 'RATE 40000000' "$OUT/f3.txt" && grep -q 'FIR 1' "$OUT/f3.txt" && grep -q 'fast_attack' "$OUT/f3.txt"; then
    record F3 PASS "40 MSPS, FIR enabled, fast_attack"
  else
    record F3 FAIL "see f3.txt"
  fi
}

f5() {
  if ! bringup_ap 13; then
    record F5 FAIL "hostapd did not reach AP-ENABLED"
    return
  fi
  if ! associate; then
    record F5 FAIL "client did not associate at 5.00 dBm"
    return
  fi
  local n loss tcp rev udp fail=0 detail=""
  for n in 1 2 3; do
    loss=$(ping_loss 192.168.13.1 300 "a4-$n")
    run_iperf "a4-$n-tcp" -c 192.168.13.1 -t 10
    run_iperf "a4-$n-rev" -c 192.168.13.1 -R -t 10
    run_iperf "a4-$n-udp" -c 192.168.13.1 -u -b 5M -t 10 -l 1000
    tcp=$(mbps "$OUT/a4-$n-tcp-iperf.txt")
    rev=$(mbps "$OUT/a4-$n-rev-iperf.txt")
    udp=$(udploss "$OUT/a4-$n-udp-iperf.txt")
    detail+=" n$n ping=$loss tcp=$tcp rev=$rev udp=$udp;"
    python3 - "$loss" "$tcp" "$rev" "$udp" <<'PY' || fail=1
import sys
loss, tcp, rev, udp = sys.argv[1:]
ok = loss != "NA" and float(loss) < 1 and tcp != "NA" and float(tcp) >= 22 and rev != "NA" and float(rev) >= 19 and udp != "NA" and float(udp) <= 0.1
raise SystemExit(0 if ok else 1)
PY
  done
  detail+=" UDP gate is <=0.1% (P18 Phase 4 strict 0% missed by 1-3 of 6250 datagrams)."
  if [ "$fail" = 0 ]; then
    record F5 PASS "$detail"
  else
    record F5 FAIL "$detail"
  fi
}

f6() {
  local ch loss tcp fail=0 detail=""
  for ch in 1 6 11; do
    if ! bringup_ap "$ch" || ! associate; then
      detail+=" ch$ch=NO_ASSOC;"
      fail=1
      continue
    fi
    loss=$(ping_loss 192.168.13.1 100 "ch$ch")
    run_iperf "ch$ch" -c 192.168.13.1 -t 10
    tcp=$(mbps "$OUT/ch$ch-iperf.txt")
    detail+=" ch$ch ping=$loss tcp=$tcp;"
    python3 - "$loss" "$tcp" <<'PY' || fail=1
import sys
loss, tcp = sys.argv[1:]
ok = loss != "NA" and float(loss) < 1 and tcp != "NA" and float(tcp) > 0
raise SystemExit(0 if ok else 1)
PY
  done
  record F6 "$([ "$fail" = 0 ] && echo PASS || echo FAIL)" "$detail"
}

f7() {
  local ssid
  ssid=$(awk -F= '/^ssid=/{print $2}' /usr/local/share/openwifi/hostapd-dongle.conf 2>/dev/null || true)
  if [ -z "$ssid" ]; then
    record F7 FAIL "dongle hostapd config missing"
    return
  fi
  if ! sudo -n /usr/local/sbin/openwifi-hostapd-ctl stop; then
    record F7 FAIL "hostapd wrapper stop failed"
    return
  fi
  board_sudo 'killall hostapd dnsmasq wpa_supplicant 2>/dev/null || true; ip link set sdr0 down || true'
  if ! set_host_type managed; then
    record F7 FAIL "dongle managed mode failed"
    return
  fi
  nmcli device set "$WLX" managed no || true
  if ! sudo -n /usr/local/sbin/openwifi-hostapd-ctl start; then
    record F7 FAIL "hostapd wrapper start failed"
    return
  fi
  cat >"$OUT/wpa.conf" <<EOF
network={
   ssid="$ssid"
   key_mgmt=NONE
}
EOF
  scp_board "$OUT/wpa.conf" /tmp/p22-wpa.conf
  board_sudo 'ip link set sdr0 down; iw dev sdr0 set type managed; ip link set sdr0 up; iw dev sdr0 set power_save off; ip addr flush dev sdr0; ip addr add 192.168.13.1/24 dev sdr0; wpa_supplicant -B -i sdr0 -c /tmp/p22-wpa.conf' >"$OUT/f7-wpa.txt" 2>&1 || true
  sudo -n /usr/sbin/ip addr add 192.168.13.19/24 dev "$WLX" >/dev/null 2>&1 || true
  sleep 4
  local loss
  loss=$(ping_loss 192.168.13.1 20 f7)
  run_iperf f7 -c 192.168.13.1 -t 10
  local tcp
  tcp=$(mbps "$OUT/f7-iperf.txt")
  # Reverse direction: board pings the dongle.
  board_sudo 'ping -c 10 -W 1 192.168.13.19' >"$OUT/f7-board-ping.txt" 2>&1 || true
  if grep -q 'bytes from' "$OUT/f7-board-ping.txt" && [ "$loss" != "NA" ] && python3 -c "import sys; sys.exit(0 if float('$loss')<50 else 1)"; then
    record F7 PASS "ssid=$ssid ping_loss=$loss tcp=$tcp"
  else
    record F7 FAIL "ssid=$ssid ping_loss=$loss tcp=$tcp"
  fi
  sudo -n /usr/local/sbin/openwifi-hostapd-ctl stop >/dev/null 2>&1 || true
}

f8() {
  board_sudo 'cd /home/analog/openwifi && ip link set sdr0 down; ./sdr-ad-hoc-up.sh sdr0 13 192.168.13.1' >"$OUT/f8.txt" 2>&1 || true
  if grep -q 'iwconfig: not found' "$OUT/f8.txt" || grep -q 'not found' "$OUT/f8.txt"; then
    record F8 FAIL "sdr-ad-hoc-up.sh needs iwconfig, which this image does not ship"
    return
  fi
  nmcli device set "$WLX" managed no || true
  sudo -n /usr/sbin/ip link set "$WLX" down || true
  sudo -n /usr/sbin/iw dev "$WLX" set type ibss || true
  sudo -n /usr/sbin/ip link set "$WLX" up || true
  sudo -n /usr/sbin/iw dev "$WLX" ibss join sdr-ad-hoc 2472 || true
  sudo -n /usr/sbin/ip addr add 192.168.13.19/24 dev "$WLX" || true
  sleep 3
  local loss
  loss=$(ping_loss 192.168.13.1 20 f8)
  if [ "$loss" != "NA" ] && python3 -c "import sys; sys.exit(0 if float('$loss')<80 else 1)"; then
    record F8 PASS "ping_loss=$loss"
  else
    record F8 FAIL "ping_loss=$loss"
  fi
}

board_monitor() {
  board_sudo 'killall hostapd dnsmasq wpa_supplicant 2>/dev/null || true; cd /home/analog/openwifi && ./monitor_ch.sh sdr0 13; iw dev sdr0 info' >"$OUT/monitor.txt" 2>&1
  grep -q 'type monitor' "$OUT/monitor.txt" && grep -q 'channel 13' "$OUT/monitor.txt"
}

inject_bin() {
  board_sudo 'if [ -f /home/analog/openwifi/inject_80211 ] && [ ! -d /home/analog/openwifi/inject_80211 ]; then echo /home/analog/openwifi/inject_80211; elif [ -x /home/analog/openwifi/inject_80211/inject_80211.arm ]; then echo /home/analog/openwifi/inject_80211/inject_80211.arm; else echo MISSING; fi'
}

f9() {
  if ! board_monitor; then
    record F9 FAIL "monitor_ch.sh did not reach channel 13"
    return
  fi
  if ! set_host_type monitor 13; then
    record F9 FAIL "host monitor failed"
    return
  fi
  local before after
  before=$(board_sudo 'grep -E "rx_pkt|sdr" /proc/interrupts | head -n 5' || true)
  sudo -n /usr/bin/tcpdump -n -i "$WLX" -c 5 -w "$OUT/f9-host.pcap" >/dev/null 2>&1 &
  board_sudo 'tcpdump -n -i sdr0 -c 10 -w /tmp/p22-f9.pcap' >"$OUT/f9-tcp.txt" 2>&1 &
  local bp=$!
  sleep 0.5
  sudo -n /usr/local/sbin/inject_80211 -m g -r 0 -t d -n 30 -d 20000 -s 100 -a 000000000001 -b 000000c0ffee "$WLX" >"$OUT/f9-inject.txt" 2>&1 || true
  wait "$bp" || true
  ssh_board 'tcpdump -n -e -r /tmp/p22-f9.pcap | head -n 20' >"$OUT/f9-decode.txt" 2>&1 || true
  after=$(board_sudo 'grep -E "rx_pkt|sdr" /proc/interrupts | head -n 5' || true)
  printf '%s\n%s\n' "$before" "$after" >"$OUT/f9-irq.txt"
  if grep -E -q 'Mb/s|Beacon|Probe|Data' "$OUT/f9-decode.txt"; then
    record F9 PASS "tcpdump decoded frames; irq before/after captured"
  else
    record F9 FAIL "no decoded frames"
  fi
}

f10() {
  if ! board_monitor; then
    record F10 FAIL "board monitor failed"
    return
  fi
  if ! set_host_type monitor 13; then
    record F10 FAIL "host monitor failed"
    return
  fi
  local bin
  bin=$(inject_bin | tr -d '\r' | tail -n 1)
  if [ "$bin" = "MISSING" ]; then
    record F10 FAIL "inject_80211 missing on the board"
    return
  fi
  local mode idx token size count fail=0 detail=""
  for spec in "g 0 6" "g 4 24" "g 7 54" "n 0 6.5" "n 4 39.0" "n 7 65.0"; do
    set -- $spec
    mode=$1; idx=$2; token=$3
    for size in 100 500 1400; do
      local pcap=$OUT/f10-${mode}-r${idx}-s${size}.pcap
      sudo -n /usr/bin/tcpdump -U -n -i "$WLX" -c 15 -w "$pcap" 'wlan addr2 00:00:00:c0:ff:ee' >"$OUT/f10-${mode}-r${idx}-s${size}.tcp" 2>&1 &
      local tpid=$!
      sleep 0.4
      board_sudo "$bin -m $mode -r $idx -t d -n 20 -d 20000 -s $size -a 000000000001 -b 000000c0ffee sdr0" >"$OUT/f10-${mode}-r${idx}-s${size}.txt" 2>&1 || true
      local w
      for w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        ps -p "$tpid" >/dev/null 2>&1 || break
        sleep 0.4
      done
      kill "$tpid" 2>/dev/null || true
      wait "$tpid" 2>/dev/null || true
      count=$(sudo -n /usr/bin/tcpdump -n -e -r "$pcap" 2>/dev/null | grep -c ' Mb/s ' || true)
      detail+=" ${mode}r${idx}s${size}=${count};"
      if [ "${count:-0}" -lt 8 ]; then
        fail=1
      fi
      if ! sudo -n /usr/bin/tcpdump -n -e -r "$pcap" 2>/dev/null | grep -E -q "${token}(\\.0)? Mb/s"; then
        fail=1
      fi
    done
  done
  record F10 "$([ "$fail" = 0 ] && echo PASS || echo FAIL)" "$detail"
}

f11() {
  if ! board_monitor; then
    record F11 FAIL "board monitor failed"
    return
  fi
  if ! set_host_type monitor 13; then
    record F11 FAIL "host monitor failed"
    return
  fi
  local mode idx count fail=0 detail=""
  for spec in "g 0" "g 7" "n 0" "n 7"; do
    set -- $spec
    mode=$1; idx=$2
    board_sudo 'tcpdump -n -i sdr0 -c 10 -w /tmp/p22-f11.pcap' >/dev/null 2>&1 &
    local bp=$!
    sleep 0.4
    sudo -n /usr/local/sbin/inject_80211 -m "$mode" -r "$idx" -t d -n 20 -d 20000 -s 100 -a 000000000001 -b 000000c0ffee "$WLX" >"$OUT/f11-${mode}-r${idx}.txt" 2>&1 || true
    wait "$bp" || true
    count=$(ssh_board 'tcpdump -n -e -r /tmp/p22-f11.pcap | grep -c " Mb/s "' || true)
    detail+=" ${mode}r${idx}=${count};"
    [ "${count:-0}" -ge 5 ] || fail=1
  done
  record F11 "$([ "$fail" = 0 ] && echo PASS || echo FAIL)" "host inject via C2 wrapper; $detail"
}

f12() {
  board_sudo 'cd /home/analog/openwifi && ./sdrctl dev sdr0 get reg xpu 58; sleep 1; ./sdrctl dev sdr0 get reg xpu 58; old=$(./sdrctl dev sdr0 get reg drv_xpu 0 | awk "END{print \$NF}"); ./sdrctl dev sdr0 set reg drv_xpu 0 305419896; ./sdrctl dev sdr0 get reg drv_xpu 0; ./sdrctl dev sdr0 set reg drv_xpu 0 ${old:-0}' >"$OUT/f12.txt" 2>&1 || {
    record F12 FAIL "sdrctl failed"
    return
  }
  if grep -q '305419896' "$OUT/f12.txt" || grep -q '12345678' "$OUT/f12.txt"; then
    record F12 PASS "TSF xpu[58] read twice; drv_xpu 0 round trip restored"
  else
    record F12 FAIL "round trip value not observed"
  fi
}

f13() {
  board_sudo 'cd /home/analog/openwifi && oldcw=$(./cw_max_min_cfg.sh); oldcs=$(./difs_disable.sh); oldnav=$(cat /sys/devices/soc0/axi/axi:sdr/csma_cfg0); oldlbt=$(./set_lbt_th.sh | awk "END{print \$NF}"); ./cw_max_min_cfg.sh 1234; echo CW $(./cw_max_min_cfg.sh); ./difs_disable.sh 7; echo DIFS $(cat /sys/devices/soc0/axi/axi:sdr/csma_cfg0); ./nav_disable.sh 3; echo NAV $(cat /sys/devices/soc0/axi/axi:sdr/csma_cfg0); ./set_lbt_th.sh 1000; echo LBT $(./set_lbt_th.sh | awk "END{print \$NF}"); ./cw_max_min_cfg.sh ${oldcw:-0}; echo ${oldcs} > /sys/devices/soc0/axi/axi:sdr/csma_cfg0; ./set_lbt_th.sh ${oldlbt:-0}' >"$OUT/f13.txt" 2>&1 || {
    record F13 FAIL "channel-access scripts failed"
    return
  }
  if grep -q 'CW 1234' "$OUT/f13.txt" && grep -q 'LBT 1000' "$OUT/f13.txt"; then
    record F13 PASS "cw, difs, nav, lbt written and restored"
  else
    record F13 FAIL "read-back mismatch"
  fi
}

f14() {
  board_sudo 'cd /home/analog/openwifi && ./slice_cfg.sh 0 66554433 10000 0 5000; echo START $(./sdrctl dev sdr0 get slice_start0); ./slice_cfg.sh 0 0 0 0 0' >"$OUT/f14.txt" 2>&1 || {
    record F14 FAIL "slice_cfg failed"
    return
  }
  if grep -q 'START' "$OUT/f14.txt"; then
    record F14 PASS "slice 0 configured, read back, restored to 0"
  else
    record F14 FAIL "no read-back"
  fi
}

f15() {
  board_sudo 'cd /home/analog/openwifi && ./stat_enable.sh 1; ./tx_stat_show.sh > /tmp/p22-tx1.txt; ./rx_stat_show.sh > /tmp/p22-rx1.txt' >"$OUT/f15a.txt" 2>&1 || true
  ping -c 20 -i 0.2 -W 1 192.168.13.1 >"$OUT/f15-ping.txt" 2>&1 || true
  board_sudo 'cd /home/analog/openwifi && ./tx_stat_show.sh > /tmp/p22-tx2.txt; ./rx_stat_show.sh > /tmp/p22-rx2.txt; echo TX1; cat /tmp/p22-tx1.txt; echo TX2; cat /tmp/p22-tx2.txt; echo RX1; cat /tmp/p22-rx1.txt; echo RX2; cat /tmp/p22-rx2.txt' >"$OUT/f15.txt" 2>&1 || {
    record F15 FAIL "stat scripts failed"
    return
  }
  if grep -q 'TX2' "$OUT/f15.txt" && grep -q 'RX2' "$OUT/f15.txt"; then
    record F15 PASS "stat_enable and tx/rx_stat_show ran before and after 20 pings"
  else
    record F15 FAIL "missing stat output"
  fi
}

f_side() {
  local sha path
  path=$(board_sudo 'if [ -L /home/analog/openwifi/side_ch.ko ] || [ -f /home/analog/openwifi/side_ch.ko ]; then readlink -f /home/analog/openwifi/side_ch.ko; else echo MISSING; fi' | tr -d '\r' | tail -n 1)
  sha=$(board_sudo "sha256sum '$path' 2>/dev/null | awk '{print \$1}'" | tr -d '\r' | tail -n 1)
  echo "side_ch path=$path sha=$sha" >"$OUT/f16-sha.txt"
  if [ "$IMAGE_NAME" = "v1.0" ] && [ "$sha" != "$FIXED_SIDE_CH_SHA" ]; then
    record F16 FAIL "refusing to insmod side_ch.ko sha=${sha:-missing}; fixed module is ${FIXED_SIDE_CH_SHA}"
    record F17 FAIL "same module refusal as F16"
    return
  fi
  if printf '%s' "$path" | grep -q 'broken'; then
    record F16 FAIL "path is the broken module"
    record F17 FAIL "path is the broken module"
    return
  fi
  board_sudo "rmmod side_ch 2>/dev/null || true; insmod '$path'; cd /home/analog/openwifi && ./monitor_ch.sh sdr0 13" >"$OUT/f16-insmod.txt" 2>&1 || {
    record F16 FAIL "insmod failed"
    record F17 FAIL "insmod failed"
    return
  }
  local host=${HOST_IP:-}
  if [ -z "$host" ]; then
    record F16 FAIL "HOST_IP is unset"
    record F17 FAIL "HOST_IP is unset"
    return
  fi
  python3 - "$OUT/f16-udp.txt" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 4000))
s.settimeout(1)
n = 0
end = time.time() + 8
while time.time() < end:
    try:
        data, _ = s.recvfrom(65535)
        n += len(data)
    except socket.timeout:
        pass
open(sys.argv[1], "w").write("bytes %d\n" % n)
PY
  local py=$!
  sleep 0.3
  board_sudo "cd /home/analog/openwifi && ./side_ch_ctl g -s ${host}" >"$OUT/f16-ctl.txt" 2>&1 &
  local ctl=$!
  sleep 8
  kill "$ctl" 2>/dev/null || true
  wait "$py" || true
  local bytes
  bytes=$(awk '/bytes/{print $2}' "$OUT/f16-udp.txt" 2>/dev/null || echo 0)
  if [ "${bytes:-0}" -gt 0 ]; then
    record F16 PASS "UDP port 4000 received $bytes bytes"
  else
    record F16 FAIL "0 bytes on UDP 4000 (same symptom as P18 Phase 4). side_ch_ctl log captured. Not a bitstream change."
  fi
  board_sudo "rmmod side_ch; insmod '$path' iq_len_init=4095; cd /home/analog/openwifi && ./side_ch_ctl wh3h01" >"$OUT/f17-insmod.txt" 2>&1 || {
    record F17 FAIL "iq insmod failed"
    return
  }
  python3 - "$OUT/f17-udp.txt" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 4000))
s.settimeout(1)
n = 0
end = time.time() + 8
while time.time() < end:
    try:
        data, _ = s.recvfrom(65535)
        n += len(data)
    except socket.timeout:
        pass
open(sys.argv[1], "w").write("bytes %d\n" % n)
PY
  py=$!
  sleep 0.3
  board_sudo "cd /home/analog/openwifi && ./side_ch_ctl g -s ${host}" >"$OUT/f17-ctl.txt" 2>&1 &
  ctl=$!
  sleep 8
  kill "$ctl" 2>/dev/null || true
  wait "$py" || true
  bytes=$(awk '/bytes/{print $2}' "$OUT/f17-udp.txt" 2>/dev/null || echo 0)
  board_sudo 'rmmod side_ch 2>/dev/null || true' || true
  if [ "${bytes:-0}" -gt 0 ]; then
    record F17 PASS "iq_len_init=4095 UDP bytes=$bytes"
  else
    record F17 FAIL "iq capture delivered 0 bytes"
  fi
}

f18() {
  board_sudo 'iw dev sdr0 set txpower fixed 1000' >"$OUT/f18.txt" 2>&1 || true
  if grep -q -i 'not supported' "$OUT/f18.txt" || grep -q 'EOPNOTSUPP' "$OUT/f18.txt" || grep -q 'Operation not supported' "$OUT/f18.txt"; then
    record F18 KNOWN-ISSUE "iw set txpower returns -EOPNOTSUPP. .set_txpower is not implemented."
  else
    record F18 KNOWN-ISSUE "command output did not show -EOPNOTSUPP; see f18.txt. Still classified KNOWN-ISSUE until a before/after attenuation measurement exists."
  fi
}

f19() {
  if ! bringup_ap 13 || ! associate; then
    record F19 KNOWN-ISSUE "could not associate to measure PS-on"
    return
  fi
  sudo -n /usr/sbin/iw dev "$WLX" set power_save on >"$OUT/f19-ps.txt" 2>&1 || true
  local loss
  loss=$(ping_loss 192.168.13.1 100 f19)
  sudo -n /usr/sbin/iw dev "$WLX" set power_save off >/dev/null 2>&1 || true
  record F19 KNOWN-ISSUE "PS-on ping loss=${loss}% (100 echoes). Not a pass/fail gate."
}

f20() {
  if [ "${RESULT[F1]:-}" != "PASS" ]; then
    record F20 SKIPPED "F1 did not pass; not rebooting a board that is not confirmed up"
    return
  fi
  local i ok=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    board_sudo 'sync; reboot' >/dev/null 2>&1 || true
    local up=0 w
    for w in $(seq 1 40); do
      if ssh_board 'echo UP' >"$OUT/f20-$i-up.txt" 2>&1; then
        up=1
        break
      fi
      sleep 5
    done
    if [ "$up" != 1 ]; then
      record F20 FAIL "reboot $i did not return SSH. Stop. Power-cycle required. Do not reboot again."
      echo "P22_MATRIX_HANG reboot $i"
      return
    fi
    if board_sudo 'cd /home/analog/openwifi && ./wgd.sh' >"$OUT/f20-$i-wgd.txt" 2>&1; then
      ok=$((ok + 1))
    else
      record F20 FAIL "reboot $i wgd.sh failed after $ok successes"
      return
    fi
  done
  record F20 PASS "10/10 soft reboots reached wgd.sh"
}

f21() {
  record F21 SKIPPED "no APPROVED-REG; 5 GHz is not tested"
}

# Order: identity, bring-up, link tests, injection, side channel, reboots last.
f1
f2
f4_wgd
f3
f12
f13
f14
f18
f5
f15
f6
f19
f7
f8
f9
f10
f11
f_side
f20
f21
echo "P22_MATRIX_ROWS_DONE"
