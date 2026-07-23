#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Discord-shop3x"
DEFAULT_SERVICE_NAME="discord-shop3x"

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m  %s\n' "$*"; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  err "กรุณารันด้วย root (หรือ sudo) เพื่อให้ติดตั้ง systemd service ได้"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

info "ติดตั้งแพ็กเกจพื้นฐาน"
apt-get update -y
apt-get install -y git python3 python3-venv python3-pip

resolve_project_dir() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -d "${here}/.git" ]]; then
    printf '%s' "$here"
    return 0
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    printf '/home/%s/%s' "$SUDO_USER" "$APP_NAME"
    return 0
  fi

  printf '/home/ubuntu/%s' "$APP_NAME"
}

ROOT_DIR="$(resolve_project_dir)"
mkdir -p "$(dirname "$ROOT_DIR")"

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  warn "ไม่พบ git repository ใน ${ROOT_DIR}"
  read -r -p "ต้องการ clone จาก GitHub ไปยัง ${ROOT_DIR} หรือไม่? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    if [[ -d "$ROOT_DIR" && "$(ls -A "$ROOT_DIR" 2>/dev/null || true)" != "" ]]; then
      warn "โฟลเดอร์ปลายทางมีไฟล์อยู่แล้ว: ${ROOT_DIR}"
      read -r -p "ยืนยันให้ลบของเดิมเพื่อ clone ใหม่? พิมพ์ YES: " confirm
      if [[ "${confirm}" != "YES" ]]; then
        err "ยกเลิก"
        exit 1
      fi
      rm -rf "$ROOT_DIR"
    fi
    git clone https://github.com/Phechr2554/Discord-shop3x.git "$ROOT_DIR"
  else
    err "ยกเลิกการติดตั้ง"
    exit 1
  fi
fi

cd "$ROOT_DIR"

if [[ ! -f "menubot.sh" ]]; then
  err "ไม่พบไฟล์ menubot.sh ใน ${ROOT_DIR}"
  exit 1
fi

chmod +x menubot.sh

if [[ -f ".venv/bin/python" ]]; then
  info "พบ virtual environment เดิม"
else
  info "สร้าง virtual environment"
  python3 -m venv .venv
fi

info "ติดตั้ง dependencies"
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

prompt_env() {
  local label="$1"
  local default="${2:-}"
  local value=""
  if [[ -n "$default" ]]; then
    read -r -p "${label} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "${label}: " value
  fi
  printf '%s' "$value"
}

info "ตั้งค่าไฟล์ .env"
DISCORD_TOKEN="$(prompt_env "ใส่ Discord bot token")"
ADMIN_IDS="$(prompt_env "ใส่ Discord user ID แอดมิน (คั่นด้วย comma)" "")"
XUI_URL="$(prompt_env "ใส่ 3x-ui URL" "")"
XUI_API_TOKEN="$(prompt_env "ใส่ 3x-ui API token (ถ้าไม่มีค่อยปล่อยว่าง)" "")"
XUI_USERNAME="$(prompt_env "ใส่ 3x-ui username (ถ้าใช้ login แบบ session)" "")"
XUI_PASSWORD="$(prompt_env "ใส่ 3x-ui password (ถ้าใช้ login แบบ session)" "")"
AIS_INBOUND_ID="$(prompt_env "AIS inbound ID" "1")"
TRUE_INBOUND_ID="$(prompt_env "TRUE inbound ID" "2")"
DB_PATH="$(prompt_env "ที่เก็บฐานข้อมูล SQLite" "/data/bot.db")"
TRUEMONEY_WALLET_PHONE="$(prompt_env "เบอร์ wallet สำหรับรับเงิน" "")"
SERVICE_NAME="$(prompt_env "ชื่อ service ระบบ" "$DEFAULT_SERVICE_NAME")"

cat > .env <<__ENV__
DISCORD_TOKEN=${DISCORD_TOKEN}
ADMIN_IDS=${ADMIN_IDS}
XUI_URL=${XUI_URL}
XUI_USERNAME=${XUI_USERNAME}
XUI_PASSWORD=${XUI_PASSWORD}
XUI_API_TOKEN=${XUI_API_TOKEN}
AIS_INBOUND_ID=${AIS_INBOUND_ID}
TRUE_INBOUND_ID=${TRUE_INBOUND_ID}
DB_PATH=${DB_PATH}
TRUEMONEY_WALLET_PHONE=${TRUEMONEY_WALLET_PHONE}
SERVICE_NAME=${SERVICE_NAME}
__ENV__

chmod 600 .env
mkdir -p "$(dirname "$DB_PATH")"

info "ติดตั้งคำสั่ง menubot"
install -m 755 "$ROOT_DIR/menubot.sh" /usr/local/bin/menubot

info "สร้าง systemd service"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<__SERVICE__
[Unit]
Description=Discord Shop 3x Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
EnvironmentFile=${ROOT_DIR}/.env
ExecStart=${ROOT_DIR}/.venv/bin/python ${ROOT_DIR}/main.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
__SERVICE__

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

info "ติดตั้งเสร็จแล้ว"
info "โฟลเดอร์หลักของโปรเจกต์: ${ROOT_DIR}"
info "พิมพ์ menubot ได้จากทุกที่ รวมถึงหน้า ~"
info "ดูสถานะ: systemctl status ${SERVICE_NAME} --no-pager"
info "ดู log สด: journalctl -u ${SERVICE_NAME} -f"
