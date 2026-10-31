#!/bin/sh
# Make ttyPS0 usable for interactive login (TX+RX).
# -L local: ignore modem control; -crtscts: no HW flow control.

TTY=/dev/ttyPS0
[ -c "$TTY" ] || exit 0

# Apply termios even if getty already opened the port
stty -F "$TTY" 115200 cs8 -cstopb -parenb -crtscts clocal cread raw -echo 2>/dev/null || true
# Restore sane cooked mode for login
stty -F "$TTY" 115200 sane -crtscts clocal 2>/dev/null || true

# Ensure inittab uses a simple getty -L (first boot / upgrades)
if [ -f /etc/inittab ] && ! grep -q 'getty -L 115200 ttyPS0' /etc/inittab; then
	sed -i 's|^.*ttyPS0.*|PS0:12345:respawn:/sbin/getty -L 115200 ttyPS0 vt102|' /etc/inittab
	# Ask init to reload (sysvinit)
	kill -HUP 1 2>/dev/null || true
fi

exit 0
