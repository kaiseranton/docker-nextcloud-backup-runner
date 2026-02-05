# 🐳 Nextcloud Docker Backup Runner

A **one-shot Docker backup container** that automatically:

- 🧩 backs up running and stopped containers using **docker-autocompose**
- 📦 backs up **Docker volumes** as compressed archives
- 🔗 detects and backs up **bind mounts** (without backing up itself)
- 🗂 backs up **Portainer stacks / compose files** (if present)
- ☁️ uploads everything to **Nextcloud via WebDAV** (rclone)
- 📬 sends a **Telegram notification** when the backup finishes (success or failure)
- 🧹 removes itself automatically after completion

Perfect for **cron jobs, systemd timers, homelabs, and multi-host setups**.

---

## ✨ Features

- 🔁 **Idempotent & one-shot** (no persistent containers)
- 🧠 **Fault-tolerant** (works even without Portainer)
- 🔐 **No Nextcloud host mounts required**
- 📂 **Timestamp-based backups**
- 🚫 **Automatically excludes its own backup directories**
- 📬 **Telegram notifications with status & summary**
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

## 🤖 Telegram Bot Setup (Optional)

The backup runner can notify you via **Telegram** once the run finishes.

### Required environment variables

| Variable | Description |
|--------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot API token |
| `TELEGRAM_CHAT_ID` | Chat ID or channel ID |

Optional:
- `TELEGRAM_SILENT=1` → send without notification sound
- `TELEGRAM_DISABLE=1` → disable Telegram notifications entirely

---

## 🚀 Run the Backup Container

Below is a **clean and readable** example `docker run` command.

```
docker run --rm \
  --name nextcloud-backup \
  -e NC_URL='https://nextcloud/remote.php/dav/files/<username>/' \
  -e NC_USER='username' \
  -e NC_PASS='password' \
  -e DEST_BASE='Backups' \
  -e HOST_TAG="$(hostname -s)" \
  -e BACKUP_DIRS='/data' \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DEST_COMPOSE='/data/compose-backups' \
  -e ONLY_RUNNING='0' \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes:ro \
  -e DEST_VOLUMES='/data/volumes-backups' \
  -v /:/host:ro \
  -e HOST_ROOT='/host' \
  -e DEST_BINDS='/data/binds-backups' \
  -e DEST_PORTAINER_STACK='/data/portainer-stacks-backups' \
  -e TELEGRAM_BOT_TOKEN='bot_token' \
  -e TELEGRAM_CHAT_ID='channel_id' \
  nextcloud-backup-runner:latest
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

## ⚠️ Security Notice

This container requires:
- access to `/var/run/docker.sock`
- read access to the host filesystem (`/host`)

👉 This effectively grants **root-level access** to the host.  
➡️ **Only run on trusted systems.**

---

## 🕒 Automation

Recommended automation options:
- `systemd` timers
- `cron`
- CI / Ansible / SSH-triggered `docker run --rm`

---

## 🤖 AI Assistance

This project was built with human experience and a bit of AI assistance.
ChatGPT was used to speed up scripting, improve robustness,
and polish documentation — all logic, testing, and final decisions remain human-driven.

---

## ❤️ Summary

A **robust, modular Docker backup runner** that backs up everything important,  
sends you a **Telegram message when done**,  
and leaves **no running containers behind**.

Happy backups! 🚀
