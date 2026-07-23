#!/usr/bin/env bash
set -euo pipefail

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m  %s\n' "$*"; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E "$0" "$@"
  fi
  err "ต้องใช้ root หรือ sudo"
  exit 1
fi

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  err "ไม่พบไฟล์ .env ที่ ${ENV_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

SERVICE_NAME="${SERVICE_NAME:-discord-shop3x}"
VENV_PY="${ROOT_DIR}/.venv/bin/python"

confirm_three() {
  local prompt="$1"
  local token="$2"
  local ans=""
  for step in 1 2 3; do
    read -r -p "${prompt} (${step}/3) พิมพ์ ${token} เพื่อยืนยัน: " ans
    if [[ "${ans}" != "${token}" ]]; then
      err "ยืนยันไม่ครบ ยกเลิก"
      exit 1
    fi
  done
}

show_status() {
  info "สถานะ service: ${SERVICE_NAME}"
  systemctl status "${SERVICE_NAME}" --no-pager || true
  echo
  info "log ล่าสุด (10 บรรทัด)"
  journalctl -u "${SERVICE_NAME}" -n 10 --no-pager || true
}

restart_service() {
  info "รีสตาร์ท service ${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"
  info "รีสตาร์ทเรียบร้อย"
}

clear_database() {
  if [[ ! -x "$VENV_PY" ]]; then
    err "ไม่พบ virtual environment: ${VENV_PY}"
    exit 1
  fi
  confirm_three "ล้างข้อมูลทั้งหมดในฐานข้อมูล" "CLEARDB"
  cd "$ROOT_DIR"
  "${VENV_PY}" - <<'PY'
import database
database.clear_all_data()
print("[INFO] ล้างข้อมูลฐานข้อมูลเรียบร้อย")
PY
  info "ล้างฐานข้อมูลเรียบร้อย"
}

uninstall_app() {
  confirm_three "ถอนการติดตั้งระบบ" "UNINSTALL"

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    systemctl stop "${SERVICE_NAME}.service" || true
    systemctl disable "${SERVICE_NAME}.service" || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
  fi

  rm -f /usr/local/bin/menubot
  info "ลบ service และคำสั่ง menubot แล้ว"

  read -r -p "ต้องการลบไฟล์โปรเจกต์ทั้งหมดที่ ${ROOT_DIR} ด้วยหรือไม่? พิมพ์ YES เพื่อลบ: " ans
  if [[ "${ans}" == "YES" ]]; then
    rm -rf "$ROOT_DIR"
    info "ลบโฟลเดอร์โปรเจกต์เรียบร้อย"
  else
    warn "คงไฟล์โปรเจกต์ไว้"
  fi
}

update_script() {
  info "อัปเดตโค้ดจาก GitHub"
  if [[ -d "${ROOT_DIR}/.git" ]]; then
    git -C "$ROOT_DIR" pull --rebase
  else
    err "โฟลเดอร์นี้ไม่ใช่ git repository"
    exit 1
  fi

  info "ติดตั้ง dependencies ใหม่"
  if [[ -x "${ROOT_DIR}/.venv/bin/pip" ]]; then
    "${ROOT_DIR}/.venv/bin/pip" install --upgrade pip
    "${ROOT_DIR}/.venv/bin/pip" install -r "${ROOT_DIR}/requirements.txt"
  else
    err "ไม่พบ virtual environment"
    exit 1
  fi

  systemctl restart "${SERVICE_NAME}"
  info "อัปเดตและรีสตาร์ทเรียบร้อย"
}

cd "$ROOT_DIR"

while true; do
  cat <<EOF_MENU
========================================
 menubot - Discord shop VPS control
 โฟลเดอร์หลัก: ${ROOT_DIR}
 service: ${SERVICE_NAME}
========================================
1) ถอนการติดตั้ง
2) ดูสถานะการทำงาน
3) รีสตาร์ทระบบ (ข้อมูลฐานข้อมูลไม่หาย)
4) ล้างข้อมูลทั้งหมดในฐานข้อมูล
5) อัปเดตสคริประบบ
0) ออก
EOF_MENU
  read -r -p "เลือกเมนู: " choice
  case "$choice" in
    1) uninstall_app ;;
    2) show_status ;;
    3) restart_service ;;
    4) clear_database ;;
    5) update_script ;;
    0) exit 0 ;;
    *) warn "เลือกไม่ถูกต้อง" ;;
  esac
  echo
done
