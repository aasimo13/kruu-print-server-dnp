#!/bin/bash
# Watches the hot folders and sends any dropped photo to the matching CUPS queue.
# HOTFOLDER is set by the systemd unit (install.sh fills in the real path); the
# default is only a fallback for running by hand.
set -u
HOTFOLDER="${HOTFOLDER_ROOT:-$HOME/print-hotfolder}"

declare -A QUEUES
QUEUES["4x6"]="Dai_Nippon_Printing_DP-QW410_4x6"
QUEUES["4x4"]="Dai_Nippon_Printing_DP-QW410_4x4"
QUEUES["4x6_2stripes"]="Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes"
QUEUES["4x6_3stripes"]="Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes"

declare -A SIZES
SIZES["4x6"]="w288h432"
SIZES["4x4"]="w288h288"
SIZES["4x6_2stripes"]="w288h432-div2"
SIZES["4x6_3stripes"]="w288h432-div3"

process_file() {
  local FOLDER="$1"
  local FILE="$2"
  local FILEPATH="$HOTFOLDER/$FOLDER/$FILE"
  local QUEUE="${QUEUES[$FOLDER]}"
  local MEDIA="${SIZES[$FOLDER]}"

  # File may still be mid-copy (esp. over Samba); wait for it to settle.
  sleep 1
  [[ -f "$FILEPATH" ]] || return

  # Only print real images; drop anything else (e.g. .DS_Store, temp files).
  if ! file "$FILEPATH" | grep -qiE "jpeg|jpg|png"; then
    rm -f "$FILEPATH"
    return
  fi

  # Send to the queue. Only delete the source once lp accepts the job, so a
  # failed submission doesn't silently lose the photo.
  if lp -d "$QUEUE" -o media="$MEDIA" -o fit-to-page "$FILEPATH"; then
    rm -f "$FILEPATH"
  else
    echo "print-watcher: lp failed for $FILEPATH (queue $QUEUE), leaving file in place" >&2
  fi
}

# Catch anything dropped while the watcher was down (boot, restart).
for FOLDER in "${!QUEUES[@]}"; do
  DIR="$HOTFOLDER/$FOLDER"
  [[ -d "$DIR" ]] || continue
  for FILEPATH in "$DIR"/*; do
    [[ -f "$FILEPATH" ]] || continue
    process_file "$FOLDER" "$(basename "$FILEPATH")"
  done
done

# read -r keeps backslashes literal; with two vars, DIR gets the first field and
# FILE gets the remainder, so filenames with spaces survive.
inotifywait -m -r -e close_write --format '%w %f' "$HOTFOLDER" | while read -r DIR FILE; do
  FOLDER=$(basename "$DIR")
  if [[ -n "${QUEUES[$FOLDER]:-}" ]]; then
    process_file "$FOLDER" "$FILE"
  fi
done
