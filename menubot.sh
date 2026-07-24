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
  err "ไม่พบไฟล์ตั้งค่า ${CONFIG_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

PROJECT_DIR="${PROJECT_DIR:-/home/ubuntu/xbot}"
SERVICE_NAME="${SERVICE_NAME:-xbot}"
SERVICE_USER="${SERVICE_USER:-root}"
ENV_FILE="${PROJECT_DIR}/.env"
VENV_PY="${PROJECT_DIR}/.venv/bin/python"

if [[ ! -d "$PROJECT_DIR" ]]; then
  err "ไม่พบโฟลเดอร์โปรเจกต์: ${PROJECT_DIR}"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  err "ไม่พบไฟล์ .env ที่ ${ENV_FILE}"
  exit 1
fi

# โหลดค่า .env ของโปรเจกต์ เพื่อให้ database.py อ่าน DB_PATH ได้ถูกต้อง
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

confirm_numeric() {
  local prompt="$1"
  local rounds="$2"
  local ans=""
  local step=1

  while [[ $step -le $rounds ]]; do
    while true; do
      printf '%s\n' "${prompt} (รอบ ${step}/${rounds})"
      printf '1) ยกเลิก\n2) ยืนยัน\n'
      read -r -p "เลือก: " ans
      case "$ans" in
        1)
          err "ยกเลิก"
          exit 1
          ;;
        2)
          break
          ;;
        *)
          warn "กรุณาเลือก 1 หรือ 2"
          ;;
      esac
    done
    step=$((step + 1))
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
  confirm_numeric "รีสตาร์ท service ${SERVICE_NAME}" 1
  info "รีสตาร์ท service ${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"
  info "รีสตาร์ทเรียบร้อย"
}

clear_database() {
  if [[ ! -x "$VENV_PY" ]]; then
    err "ไม่พบ virtual environment: ${VENV_PY}"
    exit 1
  fi
  confirm_numeric "ล้างข้อมูลทั้งหมดในฐานข้อมูล" 2
  cd "$PROJECT_DIR"
  "${VENV_PY}" - <<'PY'
import database
database.clear_all_data()
print("[INFO] ล้างข้อมูลฐานข้อมูลเรียบร้อย")
PY
  info "ล้างฐานข้อมูลเรียบร้อย"
}

uninstall_app() {
  confirm_numeric "ถอนการติดตั้งระบบ" 2

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    systemctl stop "${SERVICE_NAME}.service" || true
    systemctl disable "${SERVICE_NAME}.service" || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
  fi

  rm -f /usr/local/bin/menubot /etc/menubot.conf
  info "ลบ service, menubot และไฟล์ตั้งค่าแล้ว"

  read -r -p "ต้องการลบไฟล์โปรเจกต์ทั้งหมดที่ ${PROJECT_DIR} ด้วยหรือไม่? พิมพ์ YES เพื่อลบ: " ans
  if [[ "${ans}" == "YES" ]]; then
    rm -rf "$PROJECT_DIR"
    info "ลบโฟลเดอร์โปรเจกต์เรียบร้อย"
  else
    warn "คงไฟล์โปรเจกต์ไว้"
  fi
}

update_script() {
  confirm_numeric "อัปเดตระบบเป็นเวอร์ชันล่าสุด" 1

  if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    err "โฟลเดอร์นี้ไม่ใช่ git repository"
    exit 1
  fi

  if ! git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
    err "ไม่พบ remote origin สำหรับอัปเดต"
    exit 1
  fi

  info "ดึงข้อมูลล่าสุดจาก GitHub"
  git -C "$PROJECT_DIR" fetch origin --prune

  local head_branch=""
  head_branch="$(git -C "$PROJECT_DIR" remote show origin 2>/dev/null | awk -F': ' '/HEAD branch/ {print $2; exit}' | tr -d '\r')"

  if [[ -n "$head_branch" ]]; then
    git -C "$PROJECT_DIR" reset --hard "origin/${head_branch}"
  elif git -C "$PROJECT_DIR" show-ref --verify --quiet refs/remotes/origin/HEAD; then
    git -C "$PROJECT_DIR" reset --hard origin/HEAD
  else
    err "ไม่สามารถระบุ branch หลักของ origin ได้"
    exit 1
  fi

  info "ติดตั้ง dependencies ใหม่"
  if [[ -x "${PROJECT_DIR}/.venv/bin/pip" ]]; then
    "${PROJECT_DIR}/.venv/bin/pip" install --upgrade pip
    "${PROJECT_DIR}/.venv/bin/pip" install -r "${PROJECT_DIR}/requirements.txt"
  else
    err "ไม่พบ virtual environment"
    exit 1
  fi

  systemctl restart "${SERVICE_NAME}"
  info "อัปเดตและรีสตาร์ทเรียบร้อย"
}

cd "$PROJECT_DIR"

while true; do
  cat <<EOF_MENU
========================================
 menubot - Discord shop VPS control
 โฟลเดอร์หลัก: ${PROJECT_DIR}
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
