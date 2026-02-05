#!/usr/bin/env bash
set -euo pipefail

# =========================
# Static configuration
# =========================
BASE="/var/lib/docker/volumes/portainer_data/_data/compose"
TS="$(date +%F_%H-%M-%S)"

# =========================
# ENV configuration
# =========================
DEST_PORTAINER_STACK="${DEST_PORTAINER_STACK:-/backups/portainer-compose}"

mkdir -p "$DEST_PORTAINER_STACK"

# If the Portainer compose path does not exist -> exit cleanly
if [[ ! -d "$BASE" ]]; then
  echo "INFO: Compose base directory does not exist: $BASE"
  echo "INFO: Skipping Portainer compose backup."
  exit 0
fi

# Check if there are any project directories at all
if ! find "$BASE" -mindepth 1 -maxdepth 1 -type d -print -quit >/dev/null 2>&1; then
  echo "INFO: No projects found in compose directory: $BASE"
  echo "INFO: Skipping Portainer compose backup."
  exit 0
fi

# Iterate over all direct project directories (e.g. 4, 5)
find "$BASE" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' project_dir; do
  project_name="$(basename "$project_dir")"

  # Find all version directories vN, sort by N and select the highest one
  latest_v="$(
    find "$project_dir" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f\n' 2>/dev/null \
      | sed -E 's/^v([0-9]+)$/\1 \0/' \
      | sort -n \
      | tail -1 \
      | awk '{print $2}'
  )"

  if [[ -z "${latest_v:-}" ]]; then
    echo "[$project_name] No v* directories found – skipping."
    continue
  fi

  latest_compose="$project_dir/$latest_v/docker-compose.yml"
  if [[ ! -f "$latest_compose" ]]; then
    echo "[$project_name] $latest_v found, but no docker-compose.yml – skipping."
    continue
  fi

  # 1) Archive the entire project directory
  archive="$DEST_PORTAINER_STACK/${project_name}_${TS}.tar.gz"
  tar -C "$BASE" -czf "$archive" "$project_name"

  # 2) Save the latest docker-compose.yml separately
  latest_out="$DEST_PORTAINER_STACK/${project_name}_latest_${latest_v}_${TS}.docker-compose.yml"
  cp -a "$latest_compose" "$latest_out"

  echo "[$project_name] Backup created: $archive"
  echo "[$project_name] Latest compose file: $latest_out"
done
