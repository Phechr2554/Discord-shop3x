#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Discord-shop3x"
SERVICE_NAME="discord-shop3x"

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

cd "$ROOT_DIR"

if [[ ! -d ".git" ]]; then
  warn "โฟลเดอร์นี้ยังไม่ใช่ git repository"
  read -r -p "ต้องการ clone จาก GitHub ไปยัง /opt/${APP_NAME} แทนหรือไม่? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
TARGET_DIR="/opt/${APP_NAME}"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"
if [[ -d ".git" ]]; then
  git pull --rebase
else
  git clone https://github.com/Phechr2554/Discord-shop3x.git "$TARGET_DIR"
fi
ROOT_DIR="$TARGET_DIR"
  fi
fi

cd "$ROOT_DIR"

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
  local key="$1"
  local label="$2"
  local default="${3:-}"
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
DISCORD_TOKEN="$(prompt_env DISCORD_TOKEN "ใส่ Discord bot token")"
ADMIN_IDS="$(prompt_env ADMIN_IDS "ใส่ Discord user ID แอดมิน (คั่นด้วย comma)" "")"
XUI_URL="$(prompt_env XUI_URL "ใส่ 3x-ui URL" "")"
XUI_API_TOKEN="$(prompt_env XUI_API_TOKEN "ใส่ 3x-ui API token (ถ้าไม่มีค่อยปล่อยว่าง)" "")"
XUI_USERNAME="$(prompt_env XUI_USERNAME "ใส่ 3x-ui username (ถ้าใช้ login แบบ session)" "")"
XUI_PASSWORD="$(prompt_env XUI_PASSWORD "ใส่ 3x-ui password (ถ้าใช้ login แบบ session)" "")"
AIS_INBOUND_ID="$(prompt_env AIS_INBOUND_ID "AIS inbound ID" "1")"
TRUE_INBOUND_ID="$(prompt_env TRUE_INBOUND_ID "TRUE inbound ID" "2")"
DB_PATH="$(prompt_env DB_PATH "ที่เก็บฐานข้อมูล SQLite" "/data/bot.db")"
TRUEMONEY_WALLET_PHONE="$(prompt_env TRUEMONEY_WALLET_PHONE "เบอร์ wallet สำหรับรับเงิน" "")"
SERVICE_NAME="$(prompt_env SERVICE_NAME "ชื่อ service ระบบ" "discord-shop3x")"

cat > .env <<EOF
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
EOF

chmod 600 .env
mkdir -p "$(dirname "$DB_PATH")"

info "สร้าง systemd service"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
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
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

info "ติดตั้งเสร็จแล้ว"
info "ดูสถานะ: systemctl status ${SERVICE_NAME} --no-pager"
info "ดู log สด: journalctl -u ${SERVICE_NAME} -f"
