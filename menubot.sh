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

CONFIG_FILE="/etc/menubot.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  err "ไม่พบไฟล์คอนฟิก ${CONFIG_FILE}"
  err "ให้ติดตั้งด้วย install_vps.sh ก่อน"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

PROJECT_DIR="${PROJECT_DIR:-/home/ubuntu/xbot}"
SERVICE_NAME="${SERVICE_NAME:-xbot}"
SERVICE_UNIT="${SERVICE_NAME%.service}.service"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
VENV_PY="${VENV_DIR}/bin/python"
GITHUB_ZIP_URL="https://github.com/Phechr2554/Discord-shop3x/archive/refs/heads/main.zip"

if [[ ! -d "$PROJECT_DIR" ]]; then
  err "ไม่พบโฟลเดอร์โปรเจกต์ที่ ${PROJECT_DIR}"
  exit 1
fi

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

reload_service_unit() {
  if [[ "$SERVICE_UNIT" == *.service ]]; then
    printf '%s' "$SERVICE_UNIT"
  else
    printf '%s.service' "$SERVICE_UNIT"
  fi
}

show_status() {
  info "สถานะ service: ${SERVICE_UNIT}"
  systemctl status "${SERVICE_UNIT}" --no-pager || true
  echo
  info "log ล่าสุด (10 บรรทัด)"
  journalctl -u "${SERVICE_UNIT}" -n 10 --no-pager || true
}

restart_service() {
  info "รีสตาร์ท service ${SERVICE_UNIT}"
  systemctl restart "${SERVICE_UNIT}"
  info "รีสตาร์ทเรียบร้อย"
}

clear_database() {
  if [[ ! -x "$VENV_PY" ]]; then
    err "ไม่พบ virtual environment: ${VENV_PY}"
    exit 1
  fi
  confirm_three "ล้างข้อมูลทั้งหมดในฐานข้อมูล" "CLEARDB"
  cd "$PROJECT_DIR"
  "${VENV_PY}" - <<'PY'
import database
database.clear_all_data()
print("[INFO] ล้างข้อมูลฐานข้อมูลเรียบร้อย")
PY
  info "ล้างฐานข้อมูลเรียบร้อย"
}

uninstall_app() {
  confirm_three "ถอนการติดตั้งระบบ" "UNINSTALL"

  if systemctl list-unit-files | grep -q "^${SERVICE_UNIT}$"; then
    systemctl stop "${SERVICE_UNIT}" || true
    systemctl disable "${SERVICE_UNIT}" || true
    rm -f "/etc/systemd/system/${SERVICE_UNIT}"
    systemctl daemon-reload
  fi

  rm -f /usr/local/bin/menubot
  rm -f "$CONFIG_FILE"
  info "ลบ service และคำสั่ง menubot แล้ว"

  read -r -p "ต้องการลบไฟล์โปรเจกต์ทั้งหมดที่ ${PROJECT_DIR} ด้วยหรือไม่? พิมพ์ YES เพื่อลบ: " ans
  if [[ "${ans}" == "YES" ]]; then
    rm -rf "$PROJECT_DIR"
    info "ลบโฟลเดอร์โปรเจกต์เรียบร้อย"
  else
    warn "คงไฟล์โปรเจกต์ไว้"
  fi
}

update_from_zip() {
  local tmpdir archive extracted_dir
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/repo.zip"
  python3 - "$GITHUB_ZIP_URL" "$archive" <<'PY'
import sys
import urllib.request

url, out = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=120) as r, open(out, "wb") as f:
    f.write(r.read())
print(out)
PY
  unzip -q "$archive" -d "$tmpdir"
  extracted_dir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted_dir:-}" ]]; then
    err "แตกไฟล์อัปเดตไม่สำเร็จ"
    rm -rf "$tmpdir"
    exit 1
  fi
  rsync -a \
    --exclude '.env' \
    --exclude '.venv' \
    --exclude '*.db' \
    --exclude 'data/' \
    --exclude '__pycache__' \
    "${extracted_dir}/" "${PROJECT_DIR}/"
  rm -rf "$tmpdir"
}

update_script() {
  info "อัปเดตโค้ดระบบ"

  if [[ -d "${PROJECT_DIR}/.git" ]]; then
    git -C "$PROJECT_DIR" pull --rebase
  else
    warn "ไม่พบ git repository ในโฟลเดอร์นี้ ใช้วิธีดาวน์โหลดแพ็กเกจล่าสุดจาก GitHub แทน"
    update_from_zip
  fi

  info "ติดตั้ง dependencies ใหม่"
  if [[ -x "${VENV_DIR}/bin/pip" ]]; then
    "${VENV_DIR}/bin/pip" install --upgrade pip
    "${VENV_DIR}/bin/pip" install -r "${PROJECT_DIR}/requirements.txt"
  else
    info "ไม่พบ virtual environment เดิม กำลังสร้างใหม่"
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --upgrade pip
    "${VENV_DIR}/bin/pip" install -r "${PROJECT_DIR}/requirements.txt"
  fi

  systemctl restart "${SERVICE_UNIT}"
  info "อัปเดตและรีสตาร์ทเรียบร้อย"
}

cd "$PROJECT_DIR"

while true; do
  cat <<EOF_MENU
========================================
 menubot - Discord shop VPS control
 โฟลเดอร์หลัก: ${PROJECT_DIR}
 service: ${SERVICE_UNIT}
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
