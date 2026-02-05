#!/usr/bin/env bash
set -euo pipefail

echo "== Backup runner start: $(date -Iseconds) =="

/app/backup_docker_autocompose.sh
/app/backup_docker_volumes.sh
/app/backup_docker_bind_mounts.sh
/app/backup_portainer_stacks.sh
/app/backup_to_nextcloud.sh


echo "== Backup runner done: $(date -Iseconds) =="
