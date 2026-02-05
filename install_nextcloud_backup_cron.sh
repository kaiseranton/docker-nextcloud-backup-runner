#!/usr/bin/env bash
set -euo pipefail

# =========================
# Fixed paths & schedule
# =========================
WRAPPER="/usr/local/bin/nextcloud-backup.sh"
ENV_DIR="/etc/nextcloud-backup"
ENV_FILE="${ENV_DIR}/backup.env"

LOG_DIR="/var/log/nextcloud-backup"
LOG_FILE="${LOG_DIR}/backup.log"

CRON_FILE="/etc/cron.d/nextcloud-backup"
CRON_HOUR="5"
CRON_MIN="0"
CRON_USER="root"

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "ERROR: Run as root (sudo)."; exit 1; }
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: Missing command: $1"; exit 1; }
}

require_root
require_cmd docker

mkdir -p "$ENV_DIR" "$LOG_DIR"
chmod 700 "$ENV_DIR"
chmod 755 "$LOG_DIR"

# =========================
# Create env template ONLY if missing (never overwrite)
# =========================
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'EOF'
# === Nextcloud ===
NC_URL='https://nextcloud/remote.php/dav/files/user/'
NC_USER='user'
NC_PASS='pw'
DEST_BASE='Backups'

# === Telegram (optional but recommended) ===
TELEGRAM_BOT_TOKEN=''
TELEGRAM_CHAT_ID=''
# TELEGRAM_SILENT='1'
# TELEGRAM_DISABLE='1'

# === Options ===
ONLY_RUNNING='0'   # 0 = all containers, 1 = running only
HOST_ROOT='/host'  # bind-mount reader root inside the container
EOF
  chmod 600 "$ENV_FILE"
  echo "Created env file template: $ENV_FILE"
  echo "IMPORTANT: Edit it before the first scheduled run."
else
  echo "Env file already exists (left untouched): $ENV_FILE"
fi

# =========================
# Write/update wrapper (safe to overwrite)
# =========================
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/nextcloud-backup/backup.env"
LOG_FILE="/var/log/nextcloud-backup/backup.log"
LOCK_FILE="/var/lock/nextcloud-backup.lock"

ts() { date -Iseconds; }

[[ -f "$ENV_FILE" ]] || { echo "[$(ts)] ERROR: Missing env file: $ENV_FILE"; exit 1; }

# Load env vars
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Basic validation (required)
: "${NC_URL:?NC_URL is required}"
: "${NC_USER:?NC_USER is required}"
: "${NC_PASS:?NC_PASS is required}"
: "${DEST_BASE:?DEST_BASE is required}"

run_backup() {
  echo "[$(ts)] === Backup start ==="
  echo "[$(ts)] Host: $(hostname -s)"

  docker run --rm \
    --name nextcloud-backup \
    \
    -e NC_URL="$NC_URL" \
    -e NC_USER="$NC_USER" \
    -e NC_PASS="$NC_PASS" \
    -e DEST_BASE="$DEST_BASE" \
    -e HOST_TAG="$(hostname -s)" \
    -e BACKUP_DIRS='/data' \
    \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e DEST_COMPOSE='/data/compose-backups' \
    -e ONLY_RUNNING="${ONLY_RUNNING:-0}" \
    \
    -v /var/lib/docker/volumes:/var/lib/docker/volumes:ro \
    -e DEST_VOLUMES='/data/volumes-backups' \
    \
    -v /:/host:ro \
    -e HOST_ROOT="${HOST_ROOT:-/host}" \
    -e DEST_BINDS='/data/binds-backups' \
    \
    -e DEST_PORTAINER_STACK='/data/portainer-stacks-backups' \
    \
    -e TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}" \
    -e TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}" \
    -e TELEGRAM_SILENT="${TELEGRAM_SILENT:-0}" \
    -e TELEGRAM_DISABLE="${TELEGRAM_DISABLE:-0}" \
    \
    nextcloud-backup-runner:latest

  echo "[$(ts)] === Backup end ==="
}

# =========================
# Locking (no subshell tricks, no function export)
# - FD 9 holds the lock file
# - flock -n fails if already running -> exit cleanly
# =========================
if command -v flock >/dev/null 2>&1; then
  {
    flock -n 9 || { echo "[$(ts)] Another backup is already running. Exiting."; exit 0; }
    run_backup
  } >>"$LOG_FILE" 2>&1 9>"$LOCK_FILE"
else
  # Fallback without lock
  run_backup >>"$LOG_FILE" 2>&1
fi
EOF

chmod 755 "$WRAPPER"
echo "Installed/updated wrapper: $WRAPPER"

# =========================
# Write/update cron file (safe to overwrite)
# =========================
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${CRON_MIN} ${CRON_HOUR} * * * ${CRON_USER} ${WRAPPER}
EOF

chmod 644 "$CRON_FILE"
echo "Installed/updated cron job: $CRON_FILE (daily at ${CRON_HOUR}:$(printf '%02d' "$CRON_MIN"))"

echo
echo "✅ Done!"
echo
echo "Next steps:"
echo "1) Edit env file (if not done yet):  $ENV_FILE"
echo "2) Test run now:                    $WRAPPER"
echo "3) View logs:                       tail -n 200 -f $LOG_FILE"
