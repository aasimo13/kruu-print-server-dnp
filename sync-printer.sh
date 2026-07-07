#!/bin/bash
# Point all four queues at whatever QW410 is currently plugged in.
#
# The queue device URI embeds the printer's USB serial. Swap in a different
# QW410 (or reflash the card with another unit connected) and the old serial
# stops matching: every job then fails with "No matching printers found" and
# silently piles up, because lp reports success the moment CUPS accepts a job.
# This re-detects the connected printer and repoints the queues. Safe to re-run.
set -u

LPINFO=/usr/sbin/lpinfo
LPADMIN=/usr/sbin/lpadmin

QUEUES=(
  Dai_Nippon_Printing_DP-QW410_4x4
  Dai_Nippon_Printing_DP-QW410_4x6
  Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes
  Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes
)

# A freshly plugged printer takes a moment to enumerate on USB.
URI=""
for _ in $(seq 1 10); do
  URI="$("$LPINFO" -v 2>/dev/null | grep -i qw410 | grep -i gutenprint | head -n1 | awk '{print $2}')"
  [[ -n "$URI" ]] && break
  sleep 2
done

if [[ -z "$URI" ]]; then
  echo "sync-printer: no QW410 detected on USB" >&2
  exit 1
fi

for q in "${QUEUES[@]}"; do
  lpstat -p "$q" >/dev/null 2>&1 || continue
  CURRENT="$(lpstat -v "$q" 2>/dev/null | awk '{print $NF}')"
  if [[ "$CURRENT" != "$URI" ]]; then
    echo "sync-printer: repointing $q -> $URI (was $CURRENT)" >&2
    "$LPADMIN" -p "$q" -v "$URI"
  fi
  cupsenable "$q" 2>/dev/null || true
  cupsaccept "$q" 2>/dev/null || true
done
