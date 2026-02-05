#!/usr/bin/env bash
set -euo pipefail

START_EPOCH="$(date +%s)"
HOST_TAG="${HOST_TAG:-$(hostname -s)}"
RUN_TS="$(date +%F_%H-%M-%S)"

FAILED_STEP=""

log() { echo "[$(date -Iseconds)] $*"; }

telegram_send() {
  local status="$1"   # SUCCESS | FAILED
  local text="$2"

  # Optional disable
  if [[ "${TELEGRAM_DISABLE:-0}" == "1" ]]; then
    log "Telegram disabled (TELEGRAM_DISABLE=1)."
    return 0
  fi

  # Require env
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    log "Telegram not configured (missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID)."
    return 0
  fi

  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${text}" \
    -d "parse_mode=HTML" \
    -d "disable_notification=${TELEGRAM_SILENT:-0}" \
    >/dev/null
}

# Best-effort summary helper
count_files() {
  local p="$1"
  [[ -d "$p" ]] || { echo "0"; return; }
  find "$p" -type f 2>/dev/null | wc -l | tr -d ' '
}

size_dir() {
  local p="$1"
  [[ -d "$p" ]] || { echo "n/a"; return; }
  du -sh "$p" 2>/dev/null | awk '{print $1}' || echo "n/a"
}

notify() {
  local rc="$1"
  local end_epoch elapsed status

  end_epoch="$(date +%s)"
  elapsed="$((end_epoch - START_EPOCH))"

  if [[ "$rc" == "0" ]]; then
    status="SUCCESS"
  else
    status="FAILED"
  fi

  # These are your current env-based destinations (fallbacks match your defaults)
  local p_compose="${DEST_COMPOSE:-/backups/autocompose}"
  local p_vols="${DEST_VOLUMES:-/backups/volumes}"
  local p_binds="${DEST_BINDS:-/backups/binds}"
  local p_portainer="${DEST_PORTAINER_STACK:-/backups/portainer-compose}"

  local c_compose c_vols c_binds c_portainer
  local s_compose s_vols s_binds s_portainer

  c_compose="$(count_files "$p_compose")"
  c_vols="$(count_files "$p_vols")"
  c_binds="$(count_files "$p_binds")"
  c_portainer="$(count_files "$p_portainer")"

  s_compose="$(size_dir "$p_compose")"
  s_vols="$(size_dir "$p_vols")"
  s_binds="$(size_dir "$p_binds")"
  s_portainer="$(size_dir "$p_portainer")"

  local emoji="✅"
  [[ "$status" == "FAILED" ]] && emoji="❌"

  # Telegram needs URL-encoded newlines when using form fields sometimes; HTML with \n works fine via curl -d
  local msg
  msg="<b>${emoji} Docker Backup Runner</b>
  <b>Status:</b> ${status}
  <b>Host:</b> ${HOST_TAG}
  <b>Run:</b> ${RUN_TS}
  <b>Duration:</b> ${elapsed}s
  "
  
  if [[ -n "$FAILED_STEP" ]]; then
    msg+="<b>Failed step:</b> ${FAILED_STEP}
  "
  fi
  
  msg+="
  <b>Artifacts:</b>
  • Autocompose: ${c_compose} files (${s_compose})
  • Volumes: ${c_vols} files (${s_vols})
  • Bind mounts: ${c_binds} files (${s_binds})
  • Portainer stacks: ${c_portainer} files (${s_portainer})
  "
  telegram_send "$status" "$msg" || true
}

trap 'rc=$?; notify "$rc"; exit "$rc"' EXIT

run_step() {
  local name="$1"
  local cmd="$2"

  log "==> ${name}"
  if bash "$cmd"; then
    log "OK: ${name}"
  else
    FAILED_STEP="$name"
    log "FAIL: ${name}"
    return 1
  fi
  echo
}

echo "== Backup runner start: $(date -Iseconds) =="

run_step "Docker autocompose backup"   "/app/backup_docker_autocompose.sh"
run_step "Docker volumes backup"       "/app/backup_docker_volumes.sh"
run_step "Docker bind mounts backup"   "/app/backup_docker_bind_mounts.sh"
run_step "Portainer stacks backup"     "/app/backup_portainer_stacks.sh"
run_step "Nextcloud upload"            "/app/backup_to_nextcloud.sh"

echo "== Backup runner done: $(date -Iseconds) =="
