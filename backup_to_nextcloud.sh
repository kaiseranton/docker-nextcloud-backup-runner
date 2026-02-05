#!/usr/bin/env sh
set -eu

# -------- Required ENV --------
: "${NC_URL:?Set NC_URL, e.g. https://cloud.example.com/remote.php/dav/files/USERNAME/}"
: "${NC_USER:?Set NC_USER}"
: "${NC_PASS:?Set NC_PASS (use Nextcloud app password recommended)}"
: "${DEST_BASE:?Set DEST_BASE, e.g. Backups/docker}"
: "${BACKUP_DIRS:?Set BACKUP_DIRS (comma-separated container paths), e.g. /data/docker,/data/portainer}"

# -------- Optional ENV --------
HOST_TAG="${HOST_TAG:-$(hostname)}"
USE_HOST_TAG="${USE_HOST_TAG:-1}"          # 1 => DEST_BASE/HOST/TS
TS="${TS:-$(date +%F_%H-%M-%S)}"
RCLONE_MODE="${RCLONE_MODE:-copy}"         # copy | sync
RCLONE_REMOTE="${RCLONE_REMOTE:-nextcloud}"
RCLONE_CONFIG_PATH="${RCLONE_CONFIG_PATH:-/config/rclone/rclone.conf}"

log() { echo "[$(date -Iseconds)] $*"; }

safe_name() {
  echo "$1" | sed 's/[^a-zA-Z0-9_.-]/_/g'
}

mkdir -p "$(dirname "$RCLONE_CONFIG_PATH")"

# Build rclone config file from ENV (headless)
cat > "$RCLONE_CONFIG_PATH" <<EOF
[${RCLONE_REMOTE}]
type = webdav
url = ${NC_URL}
vendor = nextcloud
user = ${NC_USER}
pass = ${NC_PASS}
EOF

export RCLONE_CONFIG="$RCLONE_CONFIG_PATH"

# Destination root
if [ "$USE_HOST_TAG" = "1" ]; then
  DEST_ROOT="${DEST_BASE}/$(safe_name "$HOST_TAG")/${TS}"
else
  DEST_ROOT="${DEST_BASE}/${TS}"
fi

log "Remote      : ${RCLONE_REMOTE}"
log "Dest root   : ${RCLONE_REMOTE}:${DEST_ROOT}"
log "Mode        : ${RCLONE_MODE}"
log "Dirs        : ${BACKUP_DIRS}"
echo

# ensure dest root exists
rclone mkdir "${RCLONE_REMOTE}:${DEST_ROOT}" >/dev/null 2>&1 || true

# loop dirs
OLD_IFS="$IFS"
IFS=','

for src in $BACKUP_DIRS; do
  src="$(echo "$src" | xargs)"
  [ -z "$src" ] && continue

  if [ ! -d "$src" ]; then
    log "WARN: source not found (skip): $src"
    continue
  fi

  base="$(safe_name "$(basename "$src")")"
  dest="${RCLONE_REMOTE}:${DEST_ROOT}/${base}"

  log "-> $src  ==>  $dest"

  if [ "$RCLONE_MODE" = "sync" ]; then
    rclone sync "$src" "$dest" --checksum --progress
  else
    rclone copy "$src" "$dest" --checksum --progress
  fi

  echo
done

IFS="$OLD_IFS"
log "Done."
