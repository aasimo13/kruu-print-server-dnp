#!/bin/bash
#
# KRUU Print Server (DNP QW410) - one-shot installer.
#
#   git clone https://github.com/aasimo13/kruu-print-server-dnp.git
#   cd kruu-print-server-dnp
#   sudo bash install.sh
#
# Safe to re-run. It detects the Pi's username, auto-detects the plugged-in
# QW410, builds Gutenprint (skipped if already built), creates the four print
# queues, and installs both services. Plug in and power on the printer first.
#
set -euo pipefail

# Official Gutenprint release (versioned, stable URL). 5.3.5 supports the QW410.
GUTENPRINT_VERSION="5.3.5"
GUTENPRINT_URL="https://downloads.sourceforge.net/project/gimp-print/gutenprint-5.3/${GUTENPRINT_VERSION}/gutenprint-${GUTENPRINT_VERSION}.tar.xz"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Source-built Gutenprint installs to /usr/local/sbin; a distro build to /usr/sbin.
find_genppd() {
  local c
  for c in /usr/local/sbin/cups-genppd.5.3 /usr/sbin/cups-genppd.5.3; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

[[ $EUID -eq 0 ]] || die "Run with sudo:  sudo bash install.sh"

# Who owns this install? Prefer the user that ran sudo, never root.
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  TARGET_USER="$(stat -c '%U' "$0")"
fi
[[ "$TARGET_USER" != "root" ]] || die "Could not determine a non-root user to own the install. Run via 'sudo bash install.sh' as your normal user."

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || die "Could not find home directory for user '$TARGET_USER'."

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$TARGET_HOME/print-hotfolder"      # app + hot folders live here
HOTFOLDER_ROOT="$APP_DIR"

say "Installing for user '$TARGET_USER' into $APP_DIR"

# Wait out any cloud-init/apt run on a freshly flashed card.
if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
  say "Waiting for another apt/dpkg process to finish..."
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 3; done
fi

say "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  cups cups-client libusb-1.0-0-dev libcups2-dev libcupsimage2-dev \
  inotify-tools python3-flask samba build-essential wget xz-utils avahi-daemon
apt-get remove -y ipp-usb >/dev/null 2>&1 || true
systemctl enable --now cups >/dev/null 2>&1 || true

say "Configuring CUPS"
CUPSD=/etc/cups/cupsd.conf
if [[ -f "$CUPSD" ]] && ! grep -qE '^\s*Port 631' "$CUPSD"; then
  cp "$CUPSD" "$CUPSD.kruu.bak"
  sed -i 's/^Listen localhost:631/Port 631/' "$CUPSD"
  sed -i '/<Location/,/<\/Location>/ s/^\(\s*Order allow,deny\)/\1\n    Allow @local/' "$CUPSD"
fi
usermod -a -G lpadmin "$TARGET_USER" || true
cupsctl WebInterface=yes || true
systemctl restart cups
touch /var/log/cups/page_log 2>/dev/null || true

if GENPPD="$(find_genppd)"; then
  say "Gutenprint already built ($GENPPD) - skipping compile"
else
  say "Building Gutenprint from source (this takes a while on a Pi)"
  systemctl stop cups
  apt-get remove -y 'gutenprint*' >/dev/null 2>&1 || true
  rm -f /usr/lib/cups/backend/gutenprint* \
        /usr/lib/cups/filter/rastertogutenprint* \
        /usr/lib/cups/driver/gutenprint* 2>/dev/null || true

  BUILD="$(mktemp -d)"
  trap 'rm -rf "$BUILD"' EXIT
  cd "$BUILD"
  if ! wget -O gutenprint.tar.xz "$GUTENPRINT_URL"; then
    die "Could not download Gutenprint. Check the network, and run 'date' - a wrong clock on a fresh Pi breaks HTTPS. Fix with 'sudo timedatectl set-ntp true', then re-run."
  fi
  if ! tar -xJf gutenprint.tar.xz; then
    die "Gutenprint archive is corrupt (partial download). Re-run the installer."
  fi
  cd "gutenprint-${GUTENPRINT_VERSION}"
  ./configure --without-doc
  make clean && make -j"$(nproc)"
  make install
  cd "$REPO_DIR"
  rm -rf "$BUILD"
  trap - EXIT

  echo '/usr/local/lib' > /etc/ld.so.conf.d/usr-local.conf
  ldconfig
  systemctl start cups
fi
GENPPD="$(find_genppd)" || die "Gutenprint build did not produce cups-genppd.5.3"

say "Detecting the DNP QW410 (make sure it is plugged in and powered on)"
PRINTER_URI="$(lpinfo -v 2>/dev/null | grep -iE 'qw410|dnp' | grep -i 'gutenprint' | head -n1 | awk '{print $2}' || true)"
if [[ -z "$PRINTER_URI" ]]; then
  lpinfo -v 2>/dev/null | grep -i usb || true
  die "No QW410 found. Plug it in, power it on, then re-run:  sudo bash install.sh"
fi
say "Found printer: $PRINTER_URI"

say "Generating PPD"
"$GENPPD" -p /etc/cups/ppd dnp-qw410
gunzip -f /etc/cups/ppd/stp-dnp-qw410.5.3.ppd.gz
PPD=/etc/cups/ppd/stp-dnp-qw410.5.3.ppd
[[ -f "$PPD" ]] || die "Expected PPD $PPD was not generated"

say "Creating the four print queues"
declare -A PAGESIZE=(
  ["Dai_Nippon_Printing_DP-QW410_4x4"]="w288h288"
  ["Dai_Nippon_Printing_DP-QW410_4x6"]="w288h432"
  ["Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes"]="w288h432-div2"
  ["Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes"]="w288h432-div3"
)
declare -A DESC=(
  ["Dai_Nippon_Printing_DP-QW410_4x4"]="DNP QW410 - 4x4"
  ["Dai_Nippon_Printing_DP-QW410_4x6"]="DNP QW410 - 4x6"
  ["Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes"]="DNP QW410 - 4x6 2 Stripes"
  ["Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes"]="DNP QW410 - 4x6 3 Stripes"
)
for q in "${!PAGESIZE[@]}"; do
  lpadmin -x "$q" >/dev/null 2>&1 || true
  lpadmin -p "$q" -v "$PRINTER_URI" -E -P "$PPD" -D "${DESC[$q]}"
  lpadmin -p "$q" -o PageSize="${PAGESIZE[$q]}"
  cupsenable "$q" || true
  cupsaccept "$q" || true
done

say "Zeroing the 4x6 border"
for ppd in /etc/cups/ppd/Dai_Nippon_Printing_DP-QW410*.ppd; do
  [[ -f "$ppd" ]] || continue
  sed -i 's/\*ImageableArea w288h432\/4x6:\t"17.040 0.000 320.880 440.640"/\*ImageableArea w288h432\/4x6:\t"0.000 0.000 288.000 432.000"/' "$ppd"
done
systemctl restart cups

say "Creating hot folders"
for sub in 4x6 4x4 4x6_2stripes 4x6_3stripes; do
  install -d -o "$TARGET_USER" -g "$TARGET_USER" "$HOTFOLDER_ROOT/$sub"
done
chmod -R 777 "$HOTFOLDER_ROOT"

say "Installing app + watcher into $APP_DIR"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "$REPO_DIR/app.py"           "$APP_DIR/app.py"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 755 "$REPO_DIR/print-watcher.sh" "$APP_DIR/print-watcher.sh"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 755 "$REPO_DIR/sync-printer.sh"  "$APP_DIR/sync-printer.sh"

say "Installing services"
render_unit() {
  sed -e "s|__USER__|$TARGET_USER|g" \
      -e "s|__APP_DIR__|$APP_DIR|g" \
      -e "s|__HOTFOLDER_ROOT__|$HOTFOLDER_ROOT|g" \
      "$REPO_DIR/$1" > "/etc/systemd/system/$1"
}
render_unit kruu-print-web.service
render_unit print-watcher.service
render_unit kruu-printer-sync.service
systemctl unmask print-watcher kruu-print-web kruu-printer-sync >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable print-watcher kruu-print-web kruu-printer-sync
systemctl restart print-watcher kruu-print-web

say "Installing hotplug rule (re-points queues when a QW410 is plugged in)"
install -m 644 "$REPO_DIR/99-kruu-qw410.rules" /etc/udev/rules.d/99-kruu-qw410.rules
udevadm control --reload-rules || true

say "Granting the reset button passwordless cupsenable/cancel/cups-restart"
cat > /etc/sudoers.d/kruu-print <<EOF
$TARGET_USER ALL=(ALL) NOPASSWD: /usr/sbin/cupsenable, /usr/bin/systemctl restart cups, /usr/bin/cancel
EOF
chmod 440 /etc/sudoers.d/kruu-print
visudo -cf /etc/sudoers.d/kruu-print >/dev/null || { rm -f /etc/sudoers.d/kruu-print; die "sudoers file was invalid; removed it."; }

say "Configuring Samba shares"
if ! grep -q 'KRUU-Print-4x6' /etc/samba/smb.conf 2>/dev/null; then
  cat >> /etc/samba/smb.conf <<EOF

[KRUU-Print-4x6]
   path = $HOTFOLDER_ROOT/4x6
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x4]
   path = $HOTFOLDER_ROOT/4x4
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x6-2Stripes]
   path = $HOTFOLDER_ROOT/4x6_2stripes
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[KRUU-Print-4x6-3Stripes]
   path = $HOTFOLDER_ROOT/4x6_3stripes
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0777
   directory mask = 0777
EOF
fi
systemctl enable smbd >/dev/null 2>&1 || true
systemctl restart smbd || warn "smbd restart failed - Samba shares may be unavailable (web UI still works)"

say "Disabling WiFi power saving"
cat > /etc/systemd/system/wifi-powersave-off.service <<'EOF'
[Unit]
Description=Disable WiFi power saving
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/sbin/iw dev wlan0 set power_save off || /sbin/iwconfig wlan0 power off || true'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now wifi-powersave-off.service >/dev/null 2>&1 || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
say "Done."
cat <<EOF

  Web interface:  http://${IP:-<pi-ip>}:8080   (or http://$(hostname).local:8080)
  Printer URI:    $PRINTER_URI
  Installed to:   $APP_DIR  (user: $TARGET_USER)

  Check the services:
    systemctl status kruu-print-web --no-pager
    systemctl status print-watcher  --no-pager

EOF
