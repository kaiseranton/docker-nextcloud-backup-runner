#!/usr/bin/env bash
set -euo pipefail

DEST_BINDS="${DEST_BINDS:-/backups/binds}"
HOST_ROOT="${HOST_ROOT:-/}"   # on host: "/" | in container: "/host"

# ===== Static (no ENV) =====
SELF_CONTAINER_NAME="nextcloud-backup"  # <-- adjust if your runner container has a different name

EXCLUDE_SOURCES=(
  "/"                       # never back up the entire host root
  "/var/lib/docker/volumes" # volumes are handled by the volume backup script
)

TS="$(date +%F_%H-%M-%S)"
MANIFEST="$DEST_BINDS/manifest_bindmounts_${TS}.txt"
mkdir -p "$DEST_BINDS"

echo "Docker Bind-Mount Backup"
echo "Destination: $DEST_BINDS"
echo "Host root: $HOST_ROOT"
echo "Timestamp: $TS"
echo

safe_name() { echo "$1" | sed 's/[^a-zA-Z0-9_.-]/_/g'; }

is_excluded_source() {
  local src="$1"
  for ex in "${EXCLUDE_SOURCES[@]}"; do
    [[ "$src" == "$ex" ]] && return 0
    if [[ "$ex" != "/" && "$src" == "$ex/"* ]]; then
      return 0
    fi
  done
  return 1
}

# --- NEW: automatically exclude all host bind sources mounted into THIS backup container
# This prevents backing up our own backup directories.
if docker ps -a --format '{{.Names}}' | grep -qx "$SELF_CONTAINER_NAME"; then
  while IFS=$'\t' read -r src dst; do
    [[ -z "${src:-}" || -z "${dst:-}" ]] && continue

    # Exclude any host source mounted into /backups or /data,
    # as these are typically output or input directories for the backup runner.
    if [[ "$dst" == /backups* || "$dst" == /data* ]]; then
      EXCLUDE_SOURCES+=("$src")
    fi
  done < <(
    docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\t"}}{{.Destination}}{{"\n"}}{{end}}{{end}}' \
      "$SELF_CONTAINER_NAME" 2>/dev/null
  )
fi

# Optional: also exclude the current DEST_BINDS if it appears as a bind source
EXCLUDE_SOURCES+=("$DEST_BINDS")

# ---- Collect bind mounts from all containers ----
mapfile -t cids < <(docker ps -aq)
if [[ ${#cids[@]} -eq 0 ]]; then
  echo "No containers found."
  exit 0
fi

declare -A seen_sources=()

{
  echo "# Bind mounts manifest ($TS)"
  echo "# Format: container_name | source -> destination"
  echo "# NOTE: Backups are read from: HOST_ROOT + source"
  echo "# NOTE: Excluded sources:"
  printf '#   %s\n' "${EXCLUDE_SOURCES[@]}"
  echo
} > "$MANIFEST"

for cid in "${cids[@]}"; do
  cname="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
  [[ -z "${cname:-}" ]] && continue

  while IFS=$'\t' read -r src dst; do
    [[ -z "${src:-}" ]] && continue

    echo "${cname} | ${src} -> ${dst}" >> "$MANIFEST"

    # Skip conditions
    [[ "$src" == "/var/run/docker.sock" ]] && continue
    [[ "$src" == /var/lib/docker/volumes/* ]] && continue
    is_excluded_source "$src" && continue

    host_src="${HOST_ROOT%/}${src}"
    [[ -e "$host_src" ]] || continue

    [[ -n "${seen_sources[$src]+x}" ]] && continue
    seen_sources["$src"]=1

  done < <(
    docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\t"}}{{.Destination}}{{"\n"}}{{end}}{{end}}' \
      "$cid" 2>/dev/null
  )
done

echo "Manifest written: $MANIFEST"
echo

count=0
for src in "${!seen_sources[@]}"; do
  is_excluded_source "$src" && continue

  src_safe="$(safe_name "${src#/}")"
  archive="$DEST_BINDS/bind_${src_safe}_${TS}.tar.gz"

  host_src="${HOST_ROOT%/}${src}"
  echo "-> Backup: $src  (read: $host_src)"

  rel="${src#/}"
  if tar -C "$HOST_ROOT" -czf "$archive" "$rel"; then
    echo "   saved: $archive"
    ((count++)) || true
  else
    echo "   ERROR while backing up: $src"
  fi
  echo
done

echo "Done. Backed up bind-mount sources: $count"
