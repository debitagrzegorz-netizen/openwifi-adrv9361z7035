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
REPORT=${REPORT:-$ROOT/build/features/FEATURES-${IMAGE_NAME}-${STAMP}.md}
JSON=${JSON:-$ROOT/build/features/FEATURES-${IMAGE_NAME}-${STAMP}.json}
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
  # The password goes into this process environment only, never into a file.
  SSHPASS=$(python3 -I - "${OPENWIFI_VALIDATION_SH}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'export SSHPASS="\$\{SSHPASS:-([^}]+)\}"', text)
if not m:
    raise SystemExit("password source missing")
print(m.group(1))
PY
) || SSHPASS=
  export SSHPASS
fi
if [ -z "${SSHPASS:-}" ]; then
  echo "FAIL: SSHPASS is not set" >&2
  exit 2
fi

ssh_board() { sshpass -e ssh "${SSH_OPTS[@]}" "${BOARD_USER}@${BOARD_IP}" "$@"; }
board_sudo() {
  # Password on stdin. Putting it in the remote command shows it in ps.
  ssh_board "sudo -S -p '' sh -c $(printf '%q' "$1")" <<EOF
$SSHPASS
EOF
}
# sudo does not relay SIGTERM to a child (use_pty), so wait would block.
reap_pid() {
  local pid=$1 i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    ps -p "$pid" >/dev/null 2>&1 || return 0
    sleep 0.4
  done
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  if ps -p "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
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
  sudo -n /usr/sbin/ip addr flush dev "$WLX" >/dev/null 2>&1 || true
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
  # Wait for the old daemons to exit first: a dnsmasq that is still bound to
  # sdr0 makes the new one fail, and the client then gets no DHCP lease.
  board_sudo 'killall hostapd dnsmasq wpa_supplicant iperf3 2>/dev/null || true; i=0; while [ "$i" -lt 50 ] && pidof hostapd dnsmasq wpa_supplicant iperf3 >/dev/null; do i=$((i+1)); sleep 0.2; done; ip link set sdr0 down || true; iw dev sdr0 set type managed; pa=$(ip -o link show sdr0 | sed -n "s/.*permaddr \([^ ]*\).*/\1/p"); if [ -n "$pa" ]; then ip link set dev sdr0 address "$pa"; fi; ip link set sdr0 up; ip addr show sdr0 | grep -q 192.168.13.1/ || ip addr add 192.168.13.1/24 dev sdr0; cd /home/analog/openwifi && ./agc_settings.sh 1 >/tmp/p22-gain.txt 2>&1; hostapd -B -P /tmp/p22-hostapd.pid /tmp/p22-hostapd.conf > /tmp/p22-hostapd.log 2>&1; dnsmasq --conf-file=/tmp/p22-dnsmasq.conf; echo HOSTAPD_RC:$?'
  local i
  # This hostapd often reaches type AP before it prints AP-ENABLED.
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if ssh_board 'grep -q AP-ENABLED /tmp/p22-hostapd.log || iw dev sdr0 info | grep -q "type AP"'; then
      return 0
    fi
    sleep 1
  done
  ssh_board 'echo ---LOG---; cat /tmp/p22-hostapd.log; echo ---IW---; iw dev sdr0 info' >"$OUT/hostapd-fail.txt" 2>&1 || true
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

# Cold boot leaves the four DAC muxes at 0. wgd.sh is what writes DDS_SEL 2.
# F2_IDENTITY is 1 only when the boot identity is acceptable; f2_dds then
# scores the muxes and is the only place that records a passing F2.
F2_IDENTITY=0
f2() {
  F2_IDENTITY=0
  board_sudo 'sha256sum /boot/system.bit /boot/BOOT.BIN /boot/system.dtb; echo GIT $(/sbin/devmem 0x83C400FC); echo DDS $(/sbin/devmem 0x79024418) $(/sbin/devmem 0x79024458) $(/sbin/devmem 0x79024498) $(/sbin/devmem 0x790244d8); echo BUILDINFO; cat /etc/openwifi-build-info 2>/dev/null || echo BUILDINFO_MISSING' >"$OUT/f2.txt" 2>&1 || {
    record F2 FAIL "ssh or devmem failed"
    F2_IDENTITY=fail
    return
  }
  local line
  # v1.0 has no build-info file. Later images must carry the pinned
  # SRCREVs, an xpu git rev matching OPENWIFI_HW_REV, and a build-info
  # bitstream hash equal to /boot/system.bit. Boot-file hashes are
  # image-specific. DDS is not scored here: this read is before wgd.sh.
  line=$(python3 - "$OUT/f2.txt" "$IMAGE_NAME" \
    "$OPENWIFI_REV" "$OPENWIFI_HW_REV" "$ADI_HDL_REV" "$OPENOFDM_RX_REV" \
    "$META_ADI_REV" "$LINUX_ADI_REV" "$LIBIIO_REV" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
image = sys.argv[2]
expect = sys.argv[3:]
v1 = ["32ce68fda2f0f638a252e4d4064a33efa037395938bbd48a6349e8e3114d2841",
      "355f897323cf84a62a193cca4b26a120c08464f4fb1fe0a359128787f042a62e",
      "19b47419386a4a8d3472e0265c70cecfacbc537e82cf7e9bc00f83fd159d9fd6"]
git = "0x0D047D79" in t
info = "BUILDINFO_MISSING" not in t and all(s in t for s in expect)
hashes = all(s in t for s in v1)
if image == "v1.0":
    ok = hashes and git
    print(("PASS" if ok else "FAIL") + " hashes=%d git=%d buildinfo_not_required present=%d" % (int(hashes), int(git), int(info)))
else:
    # The xpu git rev register holds the first 7 hex digits of openwifi-hw.
    git = ("GIT 0x0" + expect[1][:7].upper()) in t
    bit = re.search(r"^([0-9a-f]{64})  /boot/system.bit$", t, re.M)
    bit = bool(bit) and ("bitstream_sha256=" + bit.group(1)) in t
    xsa = re.search(r"^xsa_sha256=[0-9a-f]{64}$", t, re.M) is not None
    ok = git and info and bit and xsa
    print(("PASS" if ok else "FAIL") + " git=%d buildinfo=%d bit=%d xsa=%d" % (int(git), int(info), int(bit), int(xsa)))
PY
)
  if [ "${line%% *}" = "PASS" ]; then
    F2_IDENTITY=1
  else
    F2_IDENTITY=fail
    record F2 "${line%% *}" "${line#* }"
  fi
}

f2_dds() {
  if [ "$F2_IDENTITY" != 1 ]; then
    return
  fi
  board_sudo 'echo DDS $(/sbin/devmem 0x79024418) $(/sbin/devmem 0x79024458) $(/sbin/devmem 0x79024498) $(/sbin/devmem 0x790244d8)' >"$OUT/f2-dds.txt" 2>&1 || {
    record F2 FAIL "post-wgd DDS read failed"
    return
  }
  local line
  line=$(python3 - "$OUT/f2-dds.txt" <<'PY'
import re, sys
d = open(sys.argv[1], errors="replace").read()
ms = re.findall(r"DDS((?:\s+0x[0-9A-Fa-f]+){4})", d)
parts = ms[-1].split() if ms else []
dds = parts == ["0x00000002", "0x00000002", "0x00000002", "0x00000002"]
print(("PASS" if dds else "FAIL") + " dds=%d buildinfo=1" % int(dds))
PY
)
  record F2 "${line%% *}" "${line#* }"
}

f4_wgd() {
  board_sudo 'cd /home/analog/openwifi && ./wgd.sh' >"$OUT/f4-wgd.txt" 2>&1 || {
    record F4 FAIL "wgd.sh failed"
    return
  }
  # /sys/firmware/fdt is root-only. Keep stderr out of the binary.
  board_sudo 'cat /sys/firmware/fdt' >"$OUT/f4.dtb" 2>"$OUT/f4-dtb.err" || true
  board_sudo 'cat /proc/interrupts' >"$OUT/f4-irq.txt" 2>&1 || true
  local dt=0 irq=0
  if [ -s "$OUT/f4.dtb" ] && "$ROOT/scripts/check_dtb_irqs.sh" "$OUT/f4.dtb" >"$OUT/f4-dtb.txt" 2>&1; then
    dt=1
  fi
  if grep -E -q 'xilinx-dma|sdr|tx_intf|rx_intf|openofdm|xpu' "$OUT/f4-irq.txt"; then
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
  # P23c scores the three runs together. A single run may lose up to 2%
  # of its 300 pings. The 900-ping total must stay at or under 1%. TCP uses
  # the median plus a floor. UDP stays a per-run ceiling of 0.1%.
  local n loss tcp rev udp detail="" gate
  for n in 1 2 3; do
    loss=$(ping_loss 192.168.13.1 300 "a4-$n")
    run_iperf "a4-$n-tcp" -c 192.168.13.1 -t 10
    run_iperf "a4-$n-rev" -c 192.168.13.1 -R -t 10
    run_iperf "a4-$n-udp" -c 192.168.13.1 -u -b 5M -t 10 -l 1000
    tcp=$(mbps "$OUT/a4-$n-tcp-iperf.txt")
    rev=$(mbps "$OUT/a4-$n-rev-iperf.txt")
    udp=$(udploss "$OUT/a4-$n-udp-iperf.txt")
    detail+=" n$n ping=$loss tcp=$tcp rev=$rev udp=$udp;"
  done
  gate=$(python3 - "$OUT" <<'PY'
import re, statistics, sys
from pathlib import Path
out = Path(sys.argv[1])

def ping_counts(n):
    text = (out / ("ping-a4-%d.txt" % n)).read_text(errors="replace")
    m = re.search(
        r"(\d+) packets transmitted, (\d+) (?:packets )?received",
        text, re.S)
    if not m:
        return None
    sent, got = int(m.group(1)), int(m.group(2))
    return sent, sent - got

def last_float(path, pattern):
    text = path.read_text(errors="replace")
    found = re.findall(pattern, text)
    return float(found[-1]) if found else None

pings = [ping_counts(n) for n in (1, 2, 3)]
tcps = [last_float(out / ("a4-%d-tcp-iperf.txt" % n), r"([0-9.]+)\s+Mbits/sec") for n in (1, 2, 3)]
revs = [last_float(out / ("a4-%d-rev-iperf.txt" % n), r"([0-9.]+)\s+Mbits/sec") for n in (1, 2, 3)]
udps = [last_float(out / ("a4-%d-udp-iperf.txt" % n), r"\(([0-9.]+)%\)") for n in (1, 2, 3)]
if any(p is None for p in pings) or any(v is None for v in tcps + revs + udps):
    print("FAIL incomplete")
    raise SystemExit(0)
sent = sum(p[0] for p in pings)
lost = sum(p[1] for p in pings)
agg = 100.0 * lost / sent if sent else 100.0
runs = [100.0 * p[1] / p[0] if p[0] else 100.0 for p in pings]
med_tcp = statistics.median(tcps)
med_rev = statistics.median(revs)
ok = (
    agg <= 1.0 and max(runs) <= 2.0
    and med_tcp >= 22 and min(tcps) >= 20
    and med_rev >= 19 and min(revs) >= 17
    and max(udps) <= 0.1
)
print("%s agg_ping=%.4f (%d/%d) max_ping=%.4f tcp_med=%.1f tcp_min=%.1f rev_med=%.1f rev_min=%.1f udp_max=%.4f" % (
    "PASS" if ok else "FAIL", agg, lost, sent, max(runs),
    med_tcp, min(tcps), med_rev, min(revs), max(udps)))
PY
)
  detail+=" ${gate};"
  detail+=" UDP gate is <=0.1% (P18 Phase 4 strict 0% missed by 1-3 of 6250 datagrams)."
  record F5 "${gate%% *}" "$detail"
}

# Survey the test dongle only. A BSS within four channel numbers overlaps a
# 20 MHz BSS on the channel under test. F6 uses that as the occupancy note.
scan_occupancy() {
  local tag=$1
  board_sudo 'killall hostapd dnsmasq wpa_supplicant iperf3 2>/dev/null || true; ip link set sdr0 down >/dev/null 2>&1 || true' >/dev/null 2>&1 || true
  nmcli device disconnect "$WLX" >/dev/null 2>&1 || true
  nmcli connection delete p22-reg >/dev/null 2>&1 || true
  nmcli device set "$WLX" managed no >/dev/null 2>&1 || true
  sudo -n /usr/sbin/ip link set "$WLX" down >/dev/null 2>&1 || true
  sudo -n /usr/sbin/iw dev "$WLX" set type managed >/dev/null 2>&1 || true
  sudo -n /usr/sbin/ip link set "$WLX" up >/dev/null 2>&1 || true
  : >"$OUT/scan-${tag}.txt"
  sudo -n /usr/sbin/iw dev "$WLX" scan >"$OUT/scan-${tag}.txt" 2>"$OUT/scan-${tag}.err" || \
    sudo -n /usr/sbin/iw dev "$WLX" scan >"$OUT/scan-${tag}.txt" 2>"$OUT/scan-${tag}.err" || true
  python3 - "$OUT/scan-${tag}.txt" "$OUT/scan-${tag}-summary.txt" <<'PY'
import re, sys
raw = open(sys.argv[1], errors="replace").read()
rows = {ch: [] for ch in range(1, 15)}
for block in re.split(r"\n(?=BSS )", raw):
    if not block.startswith("BSS "):
        continue
    ds = re.search(r"DS Parameter set: channel (\d+)", block)
    freq = re.search(r"freq: (\d+)", block)
    if ds:
        ch = int(ds.group(1))
    elif freq and 2412 <= int(freq.group(1)) <= 2472 and (int(freq.group(1)) - 2412) % 5 == 0:
        ch = 1 + (int(freq.group(1)) - 2412) // 5
    else:
        continue
    if ch not in rows:
        continue
    sig = re.search(r"signal: ([-\d.]+) dBm", block)
    rows[ch].append(sig.group(1) if sig else "?")
parts = []
for ch in range(1, 15):
    items = rows[ch]
    parts.append("ch%d bss=%d%s" % (ch, len(items), (" " + ",".join(items)) if items else ""))
line = "; ".join(parts)
open(sys.argv[2], "w").write(line + "\n")
print("OCC", line)
PY
}

f6() {
  # Informational. Channel 13 stays the gating channel (F5). Loss of at most
  # 3% is PASS(info) when TCP passes and the scan recorded an adjacent BSS.
  local ch loss tcp detail="" mode="PASS" klass occ
  for ch in 1 6 11; do
    scan_occupancy "pre-ch${ch}"
    if ! bringup_ap "$ch" || ! associate; then
      detail+=" ch$ch=NO_ASSOC;"
      mode=FAIL
      continue
    fi
    loss=$(ping_loss 192.168.13.1 100 "ch$ch")
    run_iperf "ch$ch" -c 192.168.13.1 -t 10
    tcp=$(mbps "$OUT/ch$ch-iperf.txt")
    occ=$(tr '\n' ' ' < "$OUT/scan-pre-ch${ch}-summary.txt" 2>/dev/null || true)
    klass=$(python3 - "$loss" "$tcp" "$OUT/scan-pre-ch${ch}-summary.txt" "$ch" <<'PY'
import re, sys
loss, tcp, path, test = sys.argv[1:]
test = int(test)
adj = False
try:
    text = open(path, errors="replace").read()
except OSError:
    text = ""
for m in re.finditer(r"ch(\d+) bss=(\d+)", text):
    ch, n = int(m.group(1)), int(m.group(2))
    if n > 0 and ch != test and abs(ch - test) <= 4:
        adj = True
if loss == "NA" or tcp == "NA":
    print("FAIL")
elif not (float(tcp) > 0):
    print("FAIL")
elif float(loss) < 1:
    print("PASS")
elif float(loss) <= 3 and adj:
    print("INFO")
else:
    print("FAIL")
PY
)
    detail+=" ch$ch ping=$loss tcp=$tcp class=$klass occ=[${occ}];"
    if [ "$klass" = "FAIL" ]; then
      mode=FAIL
    elif [ "$klass" = "INFO" ] && [ "$mode" = "PASS" ]; then
      mode="PASS(info)"
    fi
  done
  record F6 "$mode" "$detail"
}

f7() {
  local ssid
  # C2 installs this file. The neutral SSID is openwifi-test-ap. The harness
  # uses the SSID that is in the file, so an older file keeps working.
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
  # Dongle is the AP at .1. The board is the station at .19. The other way
  # around makes the host answer its own ping.
  sudo -n /usr/sbin/ip addr flush dev "$WLX" >/dev/null 2>&1 || true
  sudo -n /usr/sbin/ip addr add 192.168.13.1/24 dev "$WLX" || true
  if ! require_txpower; then
    record F7 FAIL "dongle txpower is not 5.00 dBm"
    return
  fi
  board_sudo 'ip link set sdr0 down; iw dev sdr0 set type managed; ip link set sdr0 up; iw dev sdr0 set power_save off; ip addr flush dev sdr0; ip addr add 192.168.13.19/24 dev sdr0; wpa_supplicant -B -i sdr0 -c /tmp/p22-wpa.conf' >"$OUT/f7-wpa.txt" 2>&1 || true
  local i ready=0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    ssh_board 'iw dev sdr0 link' >"$OUT/f7-link.txt" 2>&1 || true
    if grep -q Connected "$OUT/f7-link.txt"; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" != 1 ]; then
    record F7 FAIL "ssid=$ssid not associated"
    return
  fi
  if ! ip route get 192.168.13.19 | grep -q 'src 192.168.13.1'; then
    record F7 FAIL "host route to the station is not the dongle"
    return
  fi
  local loss bloss tcp rev
  loss=$(ping_loss 192.168.13.19 100 f7)
  board_sudo 'ping -c 100 -i 0.2 -W 1 192.168.13.1' >"$OUT/f7-board-ping.txt" 2>&1 || true
  bloss=$(python3 - "$OUT/f7-board-ping.txt" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
m = re.search(r"(\d+) packets transmitted, (\d+) (?:packets )?received,.*?([0-9.]+)% packet loss", t, re.S)
print(m.group(3) if m else "NA")
PY
)
  run_iperf f7 -c 192.168.13.19 -t 10
  run_iperf f7-rev -c 192.168.13.19 -R -t 10
  tcp=$(mbps "$OUT/f7-iperf.txt")
  rev=$(mbps "$OUT/f7-rev-iperf.txt")
  if [ "$loss" != "NA" ] && [ "$bloss" != "NA" ] && [ "$tcp" != "NA" ] && [ "$rev" != "NA" ] && python3 -c "import sys; sys.exit(0 if float('$loss')<1 and float('$bloss')<1 else 1)"; then
    record F7 PASS "ssid=$ssid ping_loss host=$loss board=$bloss tcp=$tcp rev=$rev"
  else
    record F7 FAIL "ssid=$ssid ping_loss host=$loss board=$bloss tcp=$tcp rev=$rev"
  fi
  sudo -n /usr/local/sbin/openwifi-hostapd-ctl stop >/dev/null 2>&1 || true
}

f8() {
  # The board's own IBSS is not visible to the RT3572 scan. The dongle creates
  # the cell at a fixed BSSID and the board joins it. A leftover 192.168.13.1
  # on the dongle would answer the ping locally.
  local bssid=02:11:22:33:44:55
  sudo -n /usr/sbin/ip addr flush dev "$WLX" >/dev/null 2>&1 || true
  nmcli device set "$WLX" managed no || true
  sudo -n /usr/sbin/ip link set "$WLX" down || true
  if ! sudo -n /usr/sbin/iw dev "$WLX" set type ibss; then
    record F8 FAIL "dongle ibss type failed"
    return
  fi
  sudo -n /usr/sbin/ip link set "$WLX" up || true
  if ! sudo -n /usr/sbin/iw dev "$WLX" ibss join sdr-ad-hoc 2472 fixed-freq "$bssid" >"$OUT/f8-join.txt" 2>&1; then
    record F8 FAIL "dongle ibss join failed"
    return
  fi
  sudo -n /usr/sbin/ip addr add 192.168.13.19/24 dev "$WLX" || true
  sudo -n /usr/sbin/iw dev "$WLX" set txpower fixed 500 >/dev/null 2>&1 || true
  if ! require_txpower; then
    record F8 FAIL "dongle txpower is not 5.00 dBm"
    return
  fi
  board_sudo "killall hostapd dnsmasq wpa_supplicant 2>/dev/null || true; cd /home/analog/openwifi && ./sdr-ad-hoc-join.sh sdr0 13 192.168.13.1 $bssid" >"$OUT/f8.txt" 2>&1 || true
  local i ready=0
  for i in 1 2 3 4 5 6 7 8; do
    board_sudo 'ping -c 3 -W 1 192.168.13.19' >"$OUT/f8-warm.txt" 2>&1 || true
    if grep -q 'bytes from' "$OUT/f8-warm.txt"; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" != 1 ]; then
    record F8 FAIL "board did not reach the dongle IBSS"
    return
  fi
  if ! ip route get 192.168.13.1 | grep -q 'src 192.168.13.19'; then
    record F8 FAIL "host route to the board is not the dongle"
    return
  fi
  # The board-side warm-up does not resolve the host's neighbour entry for
  # the board, so the first host echo could be lost. Warm up that direction
  # too; these echoes are not scored.
  ready=0
  for i in 1 2 3 4 5 6 7 8; do
    ping -c 3 -W 1 192.168.13.1 >"$OUT/f8-host-warm.txt" 2>&1 || true
    if grep -q 'bytes from' "$OUT/f8-host-warm.txt"; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" != 1 ]; then
    record F8 FAIL "host did not reach the board over the IBSS"
    return
  fi
  local loss bloss
  loss=$(ping_loss 192.168.13.1 100 f8)
  board_sudo 'ping -c 100 -i 0.2 -W 1 192.168.13.19' >"$OUT/f8-board-ping.txt" 2>&1 || true
  bloss=$(python3 - "$OUT/f8-board-ping.txt" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
m = re.search(r"(\d+) packets transmitted, (\d+) (?:packets )?received,.*?([0-9.]+)% packet loss", t, re.S)
print(m.group(3) if m else "NA")
PY
)
  if [ "$loss" != "NA" ] && [ "$bloss" != "NA" ] && python3 -c "import sys; sys.exit(0 if float('$loss')<1 and float('$bloss')<1 else 1)"; then
    record F8 PASS "ibss ping_loss host=$loss board=$bloss"
  else
    record F8 FAIL "ibss ping_loss host=$loss board=$bloss"
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
  reap_pid "$bp"
  board_sudo 'killall tcpdump 2>/dev/null || true' >/dev/null 2>&1 || true
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
      reap_pid "$tpid"
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
  local mode idx count fail=0 detail="" k bp
  for spec in "g 0" "g 7" "n 0" "n 7"; do
    set -- $spec
    mode=$1; idx=$2
    board_sudo 'rm -f /tmp/p22-f11.pcap; tcpdump -n -i sdr0 -c 10 -w /tmp/p22-f11.pcap' >/dev/null 2>&1 &
    bp=$!
    # The capture is started over SSH. Inject only after the pcap file exists,
    # so a slow login cannot consume the 20-frame burst before tcpdump listens.
    for k in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      ssh_board 'test -e /tmp/p22-f11.pcap' && break
      sleep 0.2
    done
    sleep 0.2
    sudo -n /usr/local/sbin/inject_80211 -m "$mode" -r "$idx" -t d -n 20 -d 20000 -s 100 -a 000000000001 -b 000000c0ffee "$WLX" >"$OUT/f11-${mode}-r${idx}.txt" 2>&1 || true
    reap_pid "$bp"
    board_sudo 'killall tcpdump 2>/dev/null || true' >/dev/null 2>&1 || true
    count=$(ssh_board 'tcpdump -n -e -r /tmp/p22-f11.pcap | grep -c " Mb/s "' || true)
    detail+=" ${mode}r${idx}=${count};"
    [ "${count:-0}" -ge 5 ] || fail=1
  done
  record F11 "$([ "$fail" = 0 ] && echo PASS || echo FAIL)" "host inject via C2 wrapper; $detail"
}

f12() {
  board_sudo 'cd /home/analog/openwifi && sdrctl dev sdr0 get reg xpu 58; sleep 1; sdrctl dev sdr0 get reg xpu 58; old=$(sdrctl dev sdr0 get reg drv_xpu 0 | awk "END{print \$NF}"); sdrctl dev sdr0 set reg drv_xpu 0 305419896; sdrctl dev sdr0 get reg drv_xpu 0; sdrctl dev sdr0 set reg drv_xpu 0 ${old:-0}' >"$OUT/f12.txt" 2>&1 || {
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
  # cw_max_min_cfg prints "FPGA  cw max min ...: <8 hex>" and stores hex.
  # set_lbt_th.sh prints "reg  val: <8 hex>" and takes a decimal argument.
  # A store of 0 clears the sysfs override and does not write the FPGA.
  # Do not write the show text back to sysfs.
  board_sudo "$(cat <<'EOS'
cd /home/analog/openwifi
cw_hex() {
  awk '/FPGA  cw max min for q3 to q0: [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/{v=$NF} END{print v}'
}
lbt_hex() {
  awk '/reg  val:/{v=$NF} END{print v}'
}
oldcw=$(./cw_max_min_cfg.sh | cw_hex)
oldlbt=$(./set_lbt_th.sh | lbt_hex)
echo OLD_CW ${oldcw:-missing} OLD_LBT ${oldlbt:-missing}
case $oldcw in [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) echo CW_CAPTURE_FAIL; exit 1;; esac
case $oldlbt in [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) echo LBT_CAPTURE_FAIL; exit 1;; esac
./cw_max_min_cfg.sh 1234 >/tmp/p23-cw.txt
echo CW $(cw_hex </tmp/p23-cw.txt)
./cw_max_min_cfg.sh 5678 >/tmp/p23-cw2.txt
echo CW2 $(cw_hex </tmp/p23-cw2.txt)
./set_lbt_th.sh 1000 >/tmp/p23-lbt.txt
echo LBT $(lbt_hex </tmp/p23-lbt.txt)
./cw_max_min_cfg.sh 00000000 >/tmp/p23-cw0.txt
echo SYSFS_AFTER $(grep -c 'SYSFS cw max min' /tmp/p23-cw0.txt || true)
if [ "$oldcw" != "00000000" ]; then
  ./cw_max_min_cfg.sh "$oldcw" >/tmp/p23-cw3.txt
  echo CWRESTORE $(cw_hex </tmp/p23-cw3.txt)
else
  echo CWRESTORE cleared
fi
./set_lbt_th.sh $((16#$oldlbt)) >/tmp/p23-lbt2.txt
echo LBTRESTORE $(lbt_hex </tmp/p23-lbt2.txt)
EOS
)" >"$OUT/f13.txt" 2>&1 || {
    record F13 FAIL "channel-access scripts failed"
    return
  }
  local line
  line=$(python3 - "$OUT/f13.txt" <<'PY'
import re, sys
t = open(sys.argv[1], errors="replace").read()
def one(label):
    ms = re.findall(r"(?m)^%s (\S+)\s*$" % label, t)
    return ms[-1].lower() if ms else ""
cw, cw2, lbt = one("CW"), one("CW2"), one("LBT")
cwr, lbtr, sysfs = one("CWRESTORE"), one("LBTRESTORE"), one("SYSFS_AFTER")
m = re.search(r"(?m)^OLD_CW (\S+) OLD_LBT (\S+)\s*$", t)
oldcw = m.group(1).lower() if m else ""
oldlbt = m.group(2).lower() if m else ""
hex8 = re.compile(r"[0-9a-f]{8}\Z")
if oldcw == "00000000":
    restore_ok = cwr == "cleared"
else:
    restore_ok = cwr == oldcw
ok = (cw == "00001234" and cw2 == "00005678" and sysfs == "0"
      and lbt == "000003e8" and lbtr == oldlbt
      and hex8.match(oldcw or "") and hex8.match(oldlbt or "")
      and restore_ok)
print(("PASS" if ok else "FAIL") + " cw=%s cw2=%s lbt=%s sysfs_after=%s restore=%s/%s old=%s/%s" % (cw, cw2, lbt, sysfs, cwr, lbtr, oldcw, oldlbt))
PY
)
  record F13 "${line%% *}" "${line#* }"
}

f14() {
  # Arguments are slice, mac, period, start, end. Read-back prints
  # "duration N us of slice M". Start and end must both move, then return to 0.
  board_sudo 'cd /home/analog/openwifi && ./slice_cfg.sh 0 66554433 10000 5000 8000; echo START $(sdrctl dev sdr0 get slice_start); echo END $(sdrctl dev sdr0 get slice_end); ./slice_cfg.sh 0 0 0 0 0; echo RESTORED $(sdrctl dev sdr0 get slice_start); echo ENDREST $(sdrctl dev sdr0 get slice_end)' >"$OUT/f14.txt" 2>&1 || {
    record F14 FAIL "slice_cfg failed"
    return
  }
  if grep -E -q 'START .*duration\) 5000us of slice 0' "$OUT/f14.txt" && grep -E -q 'END .*duration\) 8000us of slice 0' "$OUT/f14.txt" && grep -E -q 'RESTORED .*duration\) 0us of slice 0' "$OUT/f14.txt" && grep -E -q 'ENDREST .*duration\) 0us of slice 0' "$OUT/f14.txt"; then
    record F14 PASS "slice 0 start 5000 us and end 8000 us read back, then restored"
  else
    record F14 FAIL "read-back mismatch"
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

# Dongle AP used as the OFDM source for F16 and F17. Trigger 0 stores a
# capture only after an FCS strobe, so an AP that is up but unheard leaves
# register 20 at 0. The label stays free of the lab SSID.
side_ap_ready() {
  local dest=$1 info
  if ! require_txpower; then
    printf '%s\n' "txpower not 5.00 dBm" >"$dest"
    return 1
  fi
  info=$(sudo -n /usr/sbin/iw dev "$WLX" info 2>/dev/null || true)
  printf '%s\n' "$info" >"$dest"
  printf '%s\n' "$info" | grep -q 'type AP' || return 1
  printf '%s\n' "$info" | grep -q 'channel 13' || return 1
  printf '%s\n' "$info" | grep -q 'txpower 5.00 dBm' || return 1
  return 0
}

# RX IRQ delta while sdr0 is already in monitor. Prints the delta, or NA
# when the interrupt line cannot be parsed. A positive delta is the
# "frames are arriving" precondition; the count itself is the evidence.
side_rx_delta() {
  local dest=$1 before after
  before=$(board_sudo 'grep rx_pkt_intr /proc/interrupts | head -n 1' | tr -d '\r' | grep rx_pkt_intr | head -n 1 || true)
  sleep 2
  after=$(board_sudo 'grep rx_pkt_intr /proc/interrupts | head -n 1' | tr -d '\r' | grep rx_pkt_intr | head -n 1 || true)
  {
    printf 'BEFORE %s\n' "$before"
    printf 'AFTER %s\n' "$after"
  } >"$dest"
  python3 - "$dest" <<'PY'
import re, sys
def cpus(line):
    if "rx_pkt_intr" not in line:
        return None
    match = re.search(r":\s+([\d\s]+)", line)
    if not match:
        return None
    nums = [int(part) for part in match.group(1).split()]
    return sum(nums) if nums else None
before = after = None
for line in open(sys.argv[1], errors="replace"):
    if line.startswith("BEFORE"):
        before = cpus(line)
    elif line.startswith("AFTER"):
        after = cpus(line)
if before is None or after is None:
    print("NA")
else:
    print(after - before)
PY
}

# Reg 20 counts queued side-channel words. One CSI frame is 474 words
# (header 2 + CSI 56 + 8 equalizers of 52). One IQ frame at iq_len 4095 is
# 4096 words. A GET before a full frame is queued returns an empty payload.
# Poll for up to 10 s. The previous 8-by-0.3 s loop returned before a late
# beacon could land.
wait_side_fifo() {
  local need=$1 dest=$2 val start now tries=0
  : >"$dest"
  start=$(date +%s)
  while [ "$tries" -lt 40 ]; do
    tries=$((tries + 1))
    now=$(date +%s)
    if [ "$tries" -gt 1 ] && [ $((now - start)) -ge 10 ]; then
      return 1
    fi
    val=$(board_sudo 'cd /home/analog/openwifi && ./side_ch_ctl rh20' | tr -d '\r' | awk '/rx:/{v=$NF} END{print v}')
    printf '%s\n' "${val:-missing}" >>"$dest"
    python3 - "${val:-missing}" "$need" <<'PY' && return 0
import sys
raw, need = sys.argv[1], int(sys.argv[2])
try:
    n = int(raw, 0)
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if n >= need else 1)
PY
    now=$(date +%s)
    if [ $((now - start)) -ge 10 ]; then
      return 1
    fi
    sleep 0.3
  done
  return 1
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
  # CSI and IQ stay empty unless some station is actually transmitting.
  # The dongle AP on channel 13 is that transmitter. Beacons are enough.
  # After the earlier mode changes, reloading side_ch alone leaves register 20
  # at 0. wgd.sh reloads the SDR datapath. A capture started from that state
  # queues a full frame. Do this before the dongle AP comes up.
  board_sudo 'rmmod side_ch 2>/dev/null || true; cd /home/analog/openwifi && ./wgd.sh' >"$OUT/f16-wgd.txt" 2>&1 || {
    record F16 FAIL "wgd before the side-channel capture failed"
    record F17 FAIL "wgd before the side-channel capture failed"
    return
  }
  sudo -n /usr/local/sbin/openwifi-hostapd-ctl stop >/dev/null 2>&1 || true
  if ! set_host_type managed 13; then
    record F16 FAIL "dongle could not be set managed before the AP"
    record F17 FAIL "dongle could not be set managed before the AP"
    return
  fi
  if ! sudo -n /usr/local/sbin/openwifi-hostapd-ctl start >"$OUT/f16-hostapd.txt" 2>&1; then
    record F16 FAIL "dongle AP did not start"
    record F17 FAIL "dongle AP did not start"
    return
  fi
  sudo -n /usr/sbin/ip addr flush dev "$WLX" >/dev/null 2>&1 || true
  sudo -n /usr/sbin/ip addr add 192.168.13.1/24 dev "$WLX" >/dev/null 2>&1 || true
  local side_src="source=dongle-AP ch=13 txpower=5.00dBm"
  local f16_arrivals= f17_arrivals=
  if ! side_ap_ready "$OUT/f16-ap.txt"; then
    record F16 FAIL "dongle AP is not type AP on channel 13 at 5.00 dBm"
    record F17 FAIL "dongle AP is not type AP on channel 13 at 5.00 dBm"
    return
  fi
  # Probe writes IQ_CAPTURE only when iq_len_init>0. The FPGA bit survives
  # rmmod, and the same probe then forces the IQ trigger back to RSSI, which
  # never fires. CSI stays empty until the bit is cleared. wh3d0 is that clear.
  # Leave the bit alone until the arrival count is done: arming is the clear.
  board_sudo "killall side_ch_ctl 2>/dev/null || true; rmmod side_ch 2>/dev/null || true; insmod '$path'; cd /home/analog/openwifi && ./monitor_ch.sh sdr0 13" >"$OUT/f16-insmod.txt" 2>&1 || {
    record F16 FAIL "insmod failed"
    record F17 FAIL "insmod failed"
    return
  }
  if ! side_ap_ready "$OUT/f16-source.txt"; then
    record F16 FAIL "RF source missing before CSI arm: dongle AP is not type AP on channel 13 at 5.00 dBm"
    record F17 FAIL "RF source missing before CSI arm: dongle AP is not type AP on channel 13 at 5.00 dBm"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  fi
  f16_arrivals=$(side_rx_delta "$OUT/f16-irq.txt")
  if ! printf '%s' "$f16_arrivals" | grep -E -q '^[1-9][0-9]*$'; then
    record F16 FAIL "RF source not heard before CSI arm: ${side_src} arrivals=${f16_arrivals:-NA}"
    record F17 FAIL "RF source not heard before CSI arm: ${side_src} arrivals=${f16_arrivals:-NA}"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  fi
  board_sudo 'cd /home/analog/openwifi && ./side_ch_ctl wh3d0 && ./side_ch_ctl rh3' >"$OUT/f16-arm.txt" 2>&1 || {
    record F16 FAIL "IQ_CAPTURE clear failed"
    record F17 FAIL "IQ_CAPTURE clear failed"
    return
  }
  if ! awk '/0x[0-9a-fA-F]+/{v=$NF} END{exit !(v=="0x00000000")}' "$OUT/f16-arm.txt"; then
    record F16 FAIL "IQ_CAPTURE did not read back as 0 after wh3d0"
    record F17 FAIL "IQ_CAPTURE did not read back as 0 after wh3d0"
    return
  fi
  local host=${HOST_IP:-}
  if [ -z "$host" ]; then
    record F16 FAIL "HOST_IP is unset"
    record F17 FAIL "HOST_IP is unset"
    return
  fi
  if ! wait_side_fifo 474 "$OUT/f16-fifo.txt"; then
    record F16 FAIL "${side_src} arrivals=${f16_arrivals} FIFO stayed below 474 words before the GET: $(tr '\n' ' ' <"$OUT/f16-fifo.txt")"
  else
  python3 - "$OUT/f16-udp.txt" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 4000))
s.settimeout(1)
sizes = []
end = time.time() + 12
while time.time() < end:
    try:
        data, _ = s.recvfrom(65535)
        sizes.append(len(data))
    except socket.timeout:
        pass
ok = len(sizes) >= 18 and all(n > 0 and n % 3792 == 0 for n in sizes)
open(sys.argv[1], "w").write(
    "packets %d bytes %d ok %d sizes %s\n"
    % (len(sizes), sum(sizes), int(ok), ",".join(str(n) for n in sizes[:24]))
)
PY
  local py=$!
  sleep 0.3
  # A reader started in the remote shell holds the SSH session open, so this
  # ssh stays in the background here. SIGINT makes side_ch_ctl leave its loop
  # after the current DMA. Killing this ssh instead abandons that transfer on
  # the shared S2MM channel, and the IQ reload then never completes.
  board_sudo "cd /home/analog/openwifi && ./side_ch_ctl g -s ${host}" >"$OUT/f16-ctl.txt" 2>&1 &
  local ctl=$!
  sleep 12
  board_sudo 'killall -INT side_ch_ctl 2>/dev/null || true; i=0; while [ "$i" -lt 25 ]; do ps | grep -v grep | grep -q side_ch_ctl || break; i=$((i+1)); sleep 0.2; done; echo STOPPED' >"$OUT/f16-stop.txt" 2>&1 || true
  kill "$ctl" 2>/dev/null || true
  wait "$py" || true
  local packets
  packets=$(awk '/packets/{print $2}' "$OUT/f16-udp.txt" 2>/dev/null || echo 0)
  if grep -q 'ok 1' "$OUT/f16-udp.txt"; then
    record F16 PASS "${side_src} arrivals=${f16_arrivals} UDP port 4000 received $packets CSI datagrams, each a multiple of 3792 bytes fifo=$(tr '\n' ' ' <"$OUT/f16-fifo.txt")"
  else
    record F16 FAIL "${side_src} arrivals=${f16_arrivals} CSI capture packets=${packets:-0} (need at least 18 datagrams, each a multiple of 3792 bytes). Not a bitstream change. fifo=$(tr '\n' ' ' <"$OUT/f16-fifo.txt")"
  fi
  fi
  # Reloading side_ch drops the monitor tune. IQ with trigger 0 waits for
  # an FCS, so the receiver has to be put back on channel 13, and frames
  # have to be counted, before the capture bit is set.
  board_sudo "killall side_ch_ctl 2>/dev/null || true; rmmod side_ch && insmod '$path' iq_len_init=4095 && cd /home/analog/openwifi && ./monitor_ch.sh sdr0 13" >"$OUT/f17-insmod.txt" 2>&1 || {
    record F17 FAIL "iq insmod failed"
    return
  }
  if ! side_ap_ready "$OUT/f17-source.txt"; then
    record F17 FAIL "RF source missing before IQ arm: dongle AP is not type AP on channel 13 at 5.00 dBm"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  fi
  f17_arrivals=$(side_rx_delta "$OUT/f17-irq.txt")
  if ! printf '%s' "$f17_arrivals" | grep -E -q '^[1-9][0-9]*$'; then
    record F17 FAIL "RF source not heard before IQ arm: ${side_src} arrivals=${f17_arrivals:-NA}"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  fi
  board_sudo 'cd /home/analog/openwifi && ./side_ch_ctl wh3h01 && ./side_ch_ctl rh8' >"$OUT/f17-arm.txt" 2>&1 || {
    record F17 FAIL "${side_src} arrivals=${f17_arrivals} IQ arm failed"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  }
  if ! wait_side_fifo 4096 "$OUT/f17-fifo.txt"; then
    record F17 FAIL "${side_src} arrivals=${f17_arrivals} FIFO stayed below 4096 words before the GET: $(tr '\n' ' ' <"$OUT/f17-fifo.txt")"
    board_sudo 'rmmod side_ch 2>/dev/null || true' || true
    return
  fi
  python3 - "$OUT/f17-udp.txt" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 4000))
s.settimeout(1)
sizes = []
end = time.time() + 12
while time.time() < end:
    try:
        data, _ = s.recvfrom(65535)
        sizes.append(len(data))
    except socket.timeout:
        pass
ok = len(sizes) >= 14 and all(n == 32768 for n in sizes)
open(sys.argv[1], "w").write(
    "packets %d bytes %d ok %d sizes %s\n"
    % (len(sizes), sum(sizes), int(ok), ",".join(str(n) for n in sizes[:24]))
)
PY
  py=$!
  sleep 0.3
  board_sudo "cd /home/analog/openwifi && ./side_ch_ctl g -s ${host}" >"$OUT/f17-ctl.txt" 2>&1 &
  ctl=$!
  sleep 12
  board_sudo 'killall -INT side_ch_ctl 2>/dev/null || true; i=0; while [ "$i" -lt 25 ]; do ps | grep -v grep | grep -q side_ch_ctl || break; i=$((i+1)); sleep 0.2; done; echo STOPPED' >"$OUT/f17-stop.txt" 2>&1 || true
  kill "$ctl" 2>/dev/null || true
  wait "$py" || true
  packets=$(awk '/packets/{print $2}' "$OUT/f17-udp.txt" 2>/dev/null || echo 0)
  board_sudo 'rmmod side_ch 2>/dev/null || true' || true
  if grep -q 'ok 1' "$OUT/f17-udp.txt"; then
    record F17 PASS "${side_src} arrivals=${f17_arrivals} iq_len_init=4095 received $packets datagrams of 32768 bytes fifo=$(tr '\n' ' ' <"$OUT/f17-fifo.txt")"
  else
    record F17 FAIL "${side_src} arrivals=${f17_arrivals} IQ capture packets=${packets:-0} (need at least 14 of 32768 bytes) fifo=$(tr '\n' ' ' <"$OUT/f17-fifo.txt")"
  fi
}

f18() {
  # The TX power limit is kept by mac80211 and applied as AD9361 TX
  # attenuation when the interface runs. Measure it with the AP up, then put
  # it back: a limit left set here would weaken the AP in every later row.
  if ! bringup_ap 13; then
    record F18 FAIL "hostapd did not reach AP-ENABLED"
    return
  fi
  board_sudo 'a=/sys/bus/iio/devices/iio:device0/out_voltage0_hardwaregain
p() { echo "$1 txp=$(iw dev sdr0 info | sed -n "s/.*txpower \([-0-9.]*\) dBm.*/\1/p") att=$(sed "s/ dB.*//" $a)"; }
p BEFORE
iw dev sdr0 set txpower fixed 1000; echo SET_RC=$?; sleep 1
p LIMITED
iw dev sdr0 set txpower auto; echo AUTO_RC=$?; sleep 1
p RESTORED
killall hostapd dnsmasq 2>/dev/null; ip link set sdr0 down' >"$OUT/f18.txt" 2>&1 || true
  local verdict
  verdict=$(python3 - "$OUT/f18.txt" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
v = {}
for tag in ("BEFORE", "LIMITED", "RESTORED"):
    m = re.search(r"^%s txp=([-0-9.]+) att=([-0-9.]+)" % tag, t, re.M)
    v[tag] = (float(m.group(1)), float(m.group(2))) if m else None
rc = dict(re.findall(r"^(SET_RC|AUTO_RC)=(\d+)", t, re.M))
if None in v.values() or rc.get("SET_RC") != "0" or rc.get("AUTO_RC") != "0":
    print("FAIL incomplete measurement rc=%s; see f18.txt" % rc)
    raise SystemExit
b, l, r = v["BEFORE"], v["LIMITED"], v["RESTORED"]
d = "before=%.2fdBm/%.2fdB limited=%.2fdBm/%.2fdB restored=%.2fdBm/%.2fdB" % (b + l + r)
# The gate is the AD9361 attenuation. The txpower that iw reports can lag
# the change by seconds, so it is recorded but not scored.
ok_limit = abs((l[1] - b[1]) + 10.0) <= 0.5
ok_restore = abs(r[1] - b[1]) <= 0.25
if ok_limit and ok_restore:
    print("PASS 10 dBm limit gives -10 dB attenuation, auto restores it; " + d)
elif not ok_restore:
    print("FAIL limit not restored, later rows would run attenuated; " + d)
else:
    print("FAIL 10 dBm limit did not change attenuation by -10 dB; " + d)
PY
)
  record F18 "${verdict%% *}" "${verdict#* }"
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
    # reboot returns while this boot's sshd is still answering. An immediate
    # UP is that same boot. Wait until SSH has stayed down, then wait for
    # the new boot. "No route to host" is the link dropping, not a wgd.sh error.
    sleep 3
    local down=0 miss=0 d
    for d in $(seq 1 40); do
      if ssh_board 'echo STILL' >/dev/null 2>&1; then
        miss=0
      else
        miss=$((miss + 1))
        if [ "$miss" -ge 2 ]; then
          sleep 5
          if ! ssh_board 'echo STILL' >/dev/null 2>&1; then
            down=1
            break
          fi
          miss=0
        fi
      fi
      sleep 2
    done
    if [ "$down" != 1 ]; then
      record F20 FAIL "reboot $i did not drop SSH after $ok successes"
      return
    fi
    echo "P22_F20 reboot $i ssh dropped"
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
    # sshd and the ethernet link come back a few seconds apart.
    local ready=0 r
    for r in $(seq 1 12); do
      if board_sudo 'cd /home/analog/openwifi && ./wgd.sh' >"$OUT/f20-$i-wgd.txt" 2>&1; then
        ready=1
        break
      fi
      if ! grep -q 'Connection refused\|Connection reset\|Connection timed out\|No route to host\|Network is unreachable\|Connection closed' "$OUT/f20-$i-wgd.txt"; then
        record F20 FAIL "reboot $i wgd.sh failed after $ok successes"
        return
      fi
      sleep 5
    done
    if [ "$ready" != 1 ]; then
      record F20 FAIL "reboot $i ssh refused through the readiness window after $ok successes"
      return
    fi
    ok=$((ok + 1))
  done
  record F20 PASS "10/10 soft reboots reached wgd.sh"
}

f21() {
  record F21 SKIPPED "no APPROVED-REG; 5 GHz is not tested"
}

# Driver TX watchdog counters (sysfs tx_stall_stat, openwifi 54e77c2 and later)
# before and after every row, so a recovery or a late/net wake is tied to the
# feature that ran. Older drivers have no such file; the line is then empty.
txwd_snap() {
  echo "$1 $(ssh_board 'cat /sys/devices/soc0/axi/axi:sdr/tx_stall_stat 2>/dev/null | tr "\n" " "' 2>/dev/null)" >>"$OUT/txwd.txt"
}
row() {
  txwd_snap "$1 before"
  "$1"
  txwd_snap "$1 after"
}

# Order: identity, bring-up, DDS after wgd, link tests, injection, side channel, reboots last.
row f1
row f2
row f4_wgd
row f2_dds
row f3
row f12
row f13
row f14
row f18
row f5
row f15
row f6
row f19
row f7
row f8
row f9
row f10
row f11
row f_side
row f20
row f21
echo "P22_MATRIX_ROWS_DONE"
