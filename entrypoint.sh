#!/usr/bin/env bash
set -euo pipefail

START_EPOCH="$(date +%s)"
HOST_TAG="${HOST_TAG:-$(hostname -s)}"
RUN_TS="$(date +%F_%H-%M-%S)"

FAILED_STEP=""
SELF_CONTAINER_NAME="${SELF_CONTAINER_NAME:-nextcloud-backup}"

# Toggle: 1 = stop containers for volumes+binds backup, 0 = keep everything running
STOP_CONTAINERS_FOR_FS_BACKUP="${STOP_CONTAINERS_FOR_FS_BACKUP:-1}"

log() { echo "[$(date -Iseconds)] $*"; }

telegram_send() {
  local status="$1"
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

  local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

  # Retry configuration
  local max_attempts=10          # 10 tries
  local sleep_between=30         # 30s between tries → ~5 min total
  local connect_timeout=30       # TCP connect timeout
  local max_time=60              # max time per request

  local attempt=1
  while [[ "$attempt" -le "$max_attempts" ]]; do
    log "Telegram send attempt ${attempt}/${max_attempts}..."

    if curl -fsS \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      -X POST "$url" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${text}" \
      -d "parse_mode=HTML" \
      -d "disable_notification=${TELEGRAM_SILENT:-0}" \
      >/dev/null; then

      log "Telegram notification sent successfully."
      return 0
    fi

    log "WARN: Telegram send failed (attempt ${attempt})."
    attempt=$((attempt + 1))

    if [[ "$attempt" -le "$max_attempts" ]]; then
      log "Retrying in ${sleep_between}s..."
      sleep "$sleep_between"
    fi
  done

  log "ERROR: Telegram notification failed after ${max_attempts} attempts. Giving up."
  return 0   # IMPORTANT: never fail the backup because of Telegram
}


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

# -------------------------
# Identify THIS container (so we don't stop ourselves)
# -------------------------
SELF_CID=""
detect_self_cid() {
  local cid=""
  cid="$(grep -aoE '[0-9a-f]{64}' /proc/self/cgroup 2>/dev/null | head -n1 || true)"
  if [[ -n "$cid" ]]; then
    SELF_CID="$cid"
    return 0
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "$SELF_CONTAINER_NAME"; then
    SELF_CID="$(docker inspect -f '{{.Id}}' "$SELF_CONTAINER_NAME" 2>/dev/null || true)"
  fi
}

# -------------------------
# Stop/Start only around critical steps
# -------------------------
CRITICAL_CIDS=()
CRITICAL_WERE_STOPPED="0"

capture_running_excluding_self() {
  detect_self_cid || true

  mapfile -t CRITICAL_CIDS < <(
    docker ps --format '{{.ID}} {{.Names}}' \
      | awk -v self="$SELF_CONTAINER_NAME" '$2 != self {print $1}'
  )

  if [[ -n "${SELF_CID:-}" ]]; then
    CRITICAL_CIDS=($(printf '%s\n' "${CRITICAL_CIDS[@]}" | grep -v -F "$SELF_CID" || true))
  fi

  CRITICAL_CIDS=($(printf '%s\n' "${CRITICAL_CIDS[@]}" | sed '/^$/d'))
  log "Captured running containers for stop/restart: ${#CRITICAL_CIDS[@]}"
}

stop_for_critical_steps() {
  if [[ "$STOP_CONTAINERS_FOR_FS_BACKUP" != "1" ]]; then
    log "Skipping container stop/start (STOP_CONTAINERS_FOR_FS_BACKUP=$STOP_CONTAINERS_FOR_FS_BACKUP)"
    CRITICAL_WERE_STOPPED="0"
    CRITICAL_CIDS=()
    return 0
  fi

  capture_running_excluding_self

  if [[ ${#CRITICAL_CIDS[@]} -eq 0 ]]; then
    log "No running containers to stop for critical steps."
    CRITICAL_WERE_STOPPED="0"
    return 0
  fi

  log "Stopping containers for critical steps..."
  CRITICAL_WERE_STOPPED="1"
  if ! docker stop "${CRITICAL_CIDS[@]}" >/dev/null 2>&1; then
    log "WARN: One or more containers failed to stop (continuing)."
    docker stop "${CRITICAL_CIDS[@]}" || true
  fi
  log "Stop phase done."
}

restart_after_critical_steps() {
  if [[ "$CRITICAL_WERE_STOPPED" != "1" ]]; then
    return 0
  fi

  if [[ ${#CRITICAL_CIDS[@]} -eq 0 ]]; then
    return 0
  fi

  log "Restarting containers after critical steps..."
  if ! docker start "${CRITICAL_CIDS[@]}" >/dev/null 2>&1; then
    log "WARN: One or more containers failed to start (continuing)."
    docker start "${CRITICAL_CIDS[@]}" || true
  fi
  log "Restart phase done."
  CRITICAL_WERE_STOPPED="0"
}

notify() {
  local rc="$1"
  local end_epoch elapsed status

  end_epoch="$(date +%s)"
  elapsed="$((end_epoch - START_EPOCH))"
  [[ "$rc" == "0" ]] && status="SUCCESS" || status="FAILED"

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

  local msg
  msg="<b>${emoji} Docker Backup Runner</b>
<b>Status:</b> ${status}
<b>Host:</b> ${HOST_TAG}
<b>Run:</b> ${RUN_TS}
<b>Duration:</b> ${elapsed}s
<b>Stop during FS backup:</b> ${STOP_CONTAINERS_FOR_FS_BACKUP}
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

cleanup() {
  local rc="$1"
  restart_after_critical_steps || true
  notify "$rc" || true
}

trap 'rc=$?; cleanup "$rc"; exit "$rc"' EXIT

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

run_step "Docker autocompose backup"    "/app/backup_docker_autocompose.sh"

stop_for_critical_steps
critical_rc=0
{
  run_step "Docker volumes backup"        "/app/backup_docker_volumes.sh"
  run_step "Docker bind mounts backup"    "/app/backup_docker_bind_mounts.sh"
} || critical_rc=$?
restart_after_critical_steps || true
if [[ "$critical_rc" -ne 0 ]]; then
  exit "$critical_rc"
fi

run_step "Portainer stacks backup"      "/app/backup_portainer_stacks.sh"
run_step "Nextcloud upload"             "/app/backup_to_nextcloud.sh"

echo "== Backup runner done: $(date -Iseconds) =="
