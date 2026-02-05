#!/usr/bin/env bash
set -euo pipefail

# =========================
# ENV configuration
# =========================
DEST_COMPOSE="${DEST_COMPOSE:-/backups/autocompose}"  # destination directory
ONLY_RUNNING="${ONLY_RUNNING:-0}"                     # 0 = all containers (default), 1 = running only

# =========================
# Static configuration
# =========================
AUTOCOMPOSE_IMAGE="ghcr.io/red5d/docker-autocompose"
DOCKER_SOCK="/var/run/docker.sock"
TS="$(date +%F_%H-%M-%S)"

mkdir -p "$DEST_COMPOSE"

# =========================
# Get container list
# =========================
if [[ "$ONLY_RUNNING" == "1" ]]; then
  mapfile -t entries < <(docker ps --format '{{.ID}} {{.Names}}')
else
  mapfile -t entries < <(docker ps -a --format '{{.ID}} {{.Names}}')
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "No containers found."
  exit 0
fi

echo "Autocompose Backup"
echo "Destination: $DEST_COMPOSE"
echo "Timestamp: $TS"
echo "Containers: ${#entries[@]}"
echo

# =========================
# Run autocompose per container
# =========================
for entry in "${entries[@]}"; do
  cid="${entry%% *}"
  cname="${entry#* }"

  safe_name="$(echo "$cname" | sed 's/[^a-zA-Z0-9_.-]/_/g')"
  out_file="$DEST_COMPOSE/${safe_name}_docker-compose_${TS}.yml"
  tmp_file="${out_file}.tmp"

  echo "-> $cname ($cid)"

  if docker run --rm \
      -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
      "$AUTOCOMPOSE_IMAGE" "$cid" > "$tmp_file"; then

    if [[ ! -s "$tmp_file" ]]; then
      echo "# WARN: autocompose output was empty for $cname ($cid) at $TS" > "$tmp_file"
    fi

    mv -f "$tmp_file" "$out_file"
    echo "   saved: $out_file"
  else
    echo "   ERROR: autocompose failed for $cname ($cid)"
    echo "# ERROR: autocompose failed for $cname ($cid) at $TS" > "$out_file"
    rm -f "$tmp_file" || true
  fi

  echo
done

echo "Done."
