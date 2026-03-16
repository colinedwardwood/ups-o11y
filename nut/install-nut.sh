#!/usr/bin/env bash
# Install and configure NUT on Ubuntu 24.04 / Pi OS.
# Usage: NUT_PASSWORD="something-strong" sudo -E bash install-nut.sh
#
# NUT_UPS_NAME, NUT_UPS_DRIVER, NUT_UPS_DESC can also be overridden via env.
# If NUT_PASSWORD isn't set we'll generate one and print it — save it.

set -euo pipefail

NUT_UPS_NAME="${NUT_UPS_NAME:-eaton}"
NUT_UPS_DRIVER="${NUT_UPS_DRIVER:-usbhid-ups}"
NUT_UPS_DESC="${NUT_UPS_DESC:-Eaton 5SC 1500}"

if [[ -z "${NUT_PASSWORD:-}" ]]; then
  NUT_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#%^&*' | head -c 32)"
  echo
  echo "Generated NUT_PASSWORD: ${NUT_PASSWORD}"
  echo "Write this down — you'll need it for the exporter."
  echo
fi

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }

apt-get update -q
apt-get full-upgrade -y -q
apt-get install -y -q nut

NUT_DIR=/etc/nut

# Back up originals on first run
backup() { [[ -f "$1" && ! -f "${1}.orig" ]] && cp "$1" "${1}.orig"; }

backup "${NUT_DIR}/nut.conf"
cat > "${NUT_DIR}/nut.conf" <<'EOF'
MODE=netserver
EOF

backup "${NUT_DIR}/ups.conf"
cat > "${NUT_DIR}/ups.conf" <<EOF
maxretry = 3

[${NUT_UPS_NAME}]
  driver = ${NUT_UPS_DRIVER}
  port   = auto
  desc   = "${NUT_UPS_DESC}"
EOF

backup "${NUT_DIR}/upsd.conf"
cat > "${NUT_DIR}/upsd.conf" <<'EOF'
# localhost only — no reason to expose NUT on the network
LISTEN 127.0.0.1 3493
EOF

backup "${NUT_DIR}/upsd.users"
cat > "${NUT_DIR}/upsd.users" <<EOF
[nutuser]
  password  = ${NUT_PASSWORD}
  upsmon master
EOF
chmod 640 "${NUT_DIR}/upsd.users"
chown root:nut "${NUT_DIR}/upsd.users" 2>/dev/null || true

backup "${NUT_DIR}/upsmon.conf"
cat > "${NUT_DIR}/upsmon.conf" <<EOF
MONITOR ${NUT_UPS_NAME}@localhost 1 nutuser ${NUT_PASSWORD} primary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG /etc/killpower
RBWARNTIME 43200
NOCOMMWARNTIME 300
FINALDELAY 5
EOF
chmod 640 "${NUT_DIR}/upsmon.conf"
chown root:nut "${NUT_DIR}/upsmon.conf" 2>/dev/null || true

systemctl restart nut-driver || echo "nut-driver restart failed (UPS not connected?)"
systemctl restart nut-server
systemctl restart nut-monitor
systemctl enable nut-driver nut-server nut-monitor

echo "Done. Verify with: upsc ${NUT_UPS_NAME}@localhost"
