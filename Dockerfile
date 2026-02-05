FROM alpine:3.20
RUN apk add --no-cache bash docker-cli tar gzip rsync findutils util-linux rclone


WORKDIR /app
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

COPY backup_to_nextcloud.sh /app/backup_to_nextcloud.sh
RUN chmod +x /app/backup_to_nextcloud.sh

COPY backup_docker_autocompose.sh /app/backup_docker_autocompose.sh
RUN chmod +x /app/backup_docker_autocompose.sh

COPY backup_docker_volumes.sh /app/backup_docker_volumes.sh
RUN chmod +x /app/backup_docker_volumes.sh

COPY backup_docker_bind_mounts.sh /app/backup_docker_bind_mounts.sh
RUN chmod +x /app/backup_docker_bind_mounts.sh

COPY backup_portainer_stacks.sh /app/backup_portainer_stacks.sh
RUN chmod +x /app/backup_portainer_stacks.sh

ENTRYPOINT ["/app/entrypoint.sh"]
