#!/usr/bin/env bash
set -euo pipefail

# =========================
# ENV configuration
# =========================
VOLUME_BASE="${VOLUME_BASE:-/var/lib/docker/volumes}"
DEST_VOLUMES="${DEST_VOLUMES:-/backups/volumes}"

# Timestamp (intentionally NOT configurable via ENV – always per run)
TS="$(date +%F_%H-%M-%S)"

mkdir -p "$DEST_VOLUMES"

echo "Docker Volume Backup"
echo "Source: $VOLUME_BASE"
echo "Destination: $DEST_VOLUMES"
echo "Timestamp: $TS"
echo

# =========================
# Backup all Docker volumes
# =========================
find "$VOLUME_BASE" -mindepth 1 -maxdepth 1 -type d -print0 |
while IFS= read -r -d '' vol_dir; do
  vol_name="$(basename "$vol_dir")"
  data_dir="$vol_dir/_data"

  # Only back up volumes that contain a _data directory
  if [[ ! -d "$data_dir" ]]; then
    echo "[$vol_name] No _data directory found – skipping."
    continue
  fi

  archive="$DEST_VOLUMES/${vol_name}_${TS}.tar.gz"

  echo "-> Backing up volume: $vol_name"
  tar -C "$vol_dir" -czf "$archive" "_data"

  echo "   saved: $archive"
  echo
done

echo "All Docker volumes have been backed up."
