# 🐳 Nextcloud Docker Backup Runner

A **one-shot Docker backup container** that automatically:

- 🧩 backs up running and stopped containers using **docker-autocompose**
- 📦 backs up **Docker volumes** as compressed archives
- 🔗 detects and backs up **bind mounts** (without backing up itself)
- 🗂 backs up **Portainer stacks / compose files** (if present)
- ☁️ uploads everything to **Nextcloud via WebDAV** (rclone)
- 🧹 removes itself automatically after completion

Perfect for **cron jobs, systemd timers, homelabs, and multi-host setups**.

---

## ✨ Features

- 🔁 **Idempotent & one-shot** (no persistent containers)
- 🧠 **Fault-tolerant** (works even without Portainer or compose stacks)
- 🔐 **No Nextcloud host mounts required** (WebDAV only)
- 📂 **Timestamp-based backups**
- 🚫 **Automatically excludes its own backup directories**
- 🐧 **Runs on Debian / Ubuntu / Alpine**

---

## 📦 Build the Image

```bash
docker build -t nextcloud-backup-runner:latest .
```

---

## 🔐 Prepare Nextcloud Password (rclone)

⚠️ **Recommended:** use a **Nextcloud App Password**, not your login password.

```bash
docker run --rm -it rclone/rclone:latest obscure 'YOUR_APP_PASSWORD'
```

➡️ Use the output as `NC_PASS`.

---

## 🚀 Run the Backup Container

```bash
docker run --rm   --name nextcloud-backup     # ===== Nextcloud / rclone =====
  -e NC_URL='https://nextcloud/remote.php/dav/files/<username>/'   -e NC_USER='username'   -e NC_PASS='OBFUSCATED_RCLONE_PASSWORD'   -e DEST_BASE='Backups'   -e HOST_TAG="$(hostname -s)"   -e BACKUP_DIRS='/data'     # ===== Docker autocompose =====
  -v /var/run/docker.sock:/var/run/docker.sock   -e DEST_COMPOSE='/data/compose-backups'   -e ONLY_RUNNING='0'     # ===== Docker volumes =====
  -v /var/lib/docker/volumes:/var/lib/docker/volumes:ro   -e DEST_VOLUMES='/data/volumes-backups'     # ===== Bind mounts =====
  -v /:/host:ro   -e HOST_ROOT='/host'   -e DEST_BINDS='/data/binds-backups'     # ===== Portainer stacks =====
  -e DEST_PORTAINER_STACK='/data/portainer-stacks-backups'     # ===== Local backup root =====
  -v /srv/backups/docker:/data     nextcloud-backup-runner:latest
```

---

## 🗂 Backup Structure in Nextcloud

```text
Backups/
└── <hostname>/
    └── <timestamp>/
        ├── compose-backups/
        ├── volumes-backups/
        ├── binds-backups/
        └── portainer-stacks-backups/
```

Each run creates **one timestamped backup directory**.

---

## ⚙️ Important Environment Variables

| Variable | Description |
|--------|-------------|
| `NC_URL` | Nextcloud WebDAV URL |
| `NC_USER` | Nextcloud username |
| `NC_PASS` | rclone-obfuscated password |
| `DEST_BASE` | Base directory in Nextcloud |
| `HOST_TAG` | Hostname used in backup path |
| `BACKUP_DIRS` | Local directories to upload |
| `DEST_COMPOSE` | Destination for autocompose backups |
| `ONLY_RUNNING` | `0` = all containers, `1` = running only |
| `DEST_VOLUMES` | Destination for volume backups |
| `DEST_BINDS` | Destination for bind-mount backups |
| `DEST_PORTAINER_STACK` | Destination for Portainer stack backups |
| `HOST_ROOT` | Host filesystem root inside container |

---

## ⚠️ Security Notice

This container requires:
- access to `/var/run/docker.sock`
- read access to the host filesystem (`/host`)

👉 This effectively grants **root-level access** to the host.  
➡️ **Only run on trusted systems.**

---

## 🕒 Automation

Recommended ways to automate:
- `systemd` timer
- `cron`
- CI / Ansible / SSH-triggered `docker run --rm`

---

## ❤️ Summary

A **robust, modular Docker backup runner** that backs up everything important  
and leaves **no running containers behind**.

Happy backups! 🚀
