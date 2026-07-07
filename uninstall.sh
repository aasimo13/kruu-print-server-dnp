#!/bin/bash
# Remove the KRUU print server. Leaves Gutenprint and CUPS installed.
#   sudo bash uninstall.sh
set -u
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash uninstall.sh" >&2; exit 1; }

systemctl disable --now print-watcher kruu-print-web wifi-powersave-off.service 2>/dev/null || true
rm -f /etc/systemd/system/print-watcher.service \
      /etc/systemd/system/kruu-print-web.service \
      /etc/systemd/system/wifi-powersave-off.service
systemctl daemon-reload

for q in Dai_Nippon_Printing_DP-QW410_4x4 \
         Dai_Nippon_Printing_DP-QW410_4x6 \
         Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes \
         Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes; do
  lpadmin -x "$q" 2>/dev/null || true
done

rm -f /etc/sudoers.d/kruu-print

echo "Removed services, queues, and sudoers entry."
echo "Hot folders and Samba shares were left in place. Remove them by hand if you want them gone."
