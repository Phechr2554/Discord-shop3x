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
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
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

edit_env() {
  local tmp_env
  local editor_bin=""

  if command -v nano >/dev/null 2>&1; then
    editor_bin="nano"
  elif command -v vi >/dev/null 2>&1; then
    editor_bin="vi"
  else
    err "ไม่พบโปรแกรมแก้ไขไฟล์ (nano/vi)"
    exit 1
  fi

  tmp_env="$(mktemp /tmp/xbot-env.XXXXXX)"
  cat > "$tmp_env" <<__ENV__
# ตั้งค่าไฟล์ .env
# แก้ค่าแล้วกด Ctrl+O เพื่อบันทึก และ Ctrl+X เพื่อออก
# ตัวอย่างรูปแบบ:
# DISCORD_TOKEN="..."
# ADMIN_IDS="..."

DISCORD_TOKEN="${DISCORD_TOKEN:-}"
ADMIN_IDS="${ADMIN_IDS:-}"
XUI_URL="${XUI_URL:-}"
XUI_API_TOKEN="${XUI_API_TOKEN:-}"
XUI_USERNAME="${XUI_USERNAME:-}"
XUI_PASSWORD="${XUI_PASSWORD:-}"
AIS_INBOUND_ID="${AIS_INBOUND_ID:-1}"
TRUE_INBOUND_ID="${TRUE_INBOUND_ID:-2}"
DB_PATH="${DB_PATH:-/data/bot.db}"
TRUEMONEY_WALLET_PHONE="${TRUEMONEY_WALLET_PHONE:-}"
SERVICE_NAME="${SERVICE_NAME:-xbot}"
__ENV__

  info "ตั้งค่าไฟล์ .env"
  info "เปิดไฟล์ด้วย ${editor_bin}: ${tmp_env}"
  "${editor_bin}" "$tmp_env"

  if ! bash -n "$tmp_env"; then
    err "ไฟล์ .env มี syntax ไม่ถูกต้อง"
    rm -f "$tmp_env"
    exit 1
  fi

  cp "$tmp_env" "$ENV_FILE"
  rm -f "$tmp_env"
  chmod 600 "$ENV_FILE"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$ENV_FILE" 2>/dev/null || true

  set -a
  source "$ENV_FILE"
  set +a

  mkdir -p "$(dirname "${DB_PATH:-/data/bot.db}")" 2>/dev/null || true
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$PROJECT_DIR" 2>/dev/null || true

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "รีสตาร์ท service เพื่อให้ค่าทำงานทันที"
    systemctl restart "${SERVICE_NAME}"
  elif systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    info "เริ่ม service เพื่อให้ค่าทำงานทันที"
    systemctl start "${SERVICE_NAME}" || true
  fi

  info "บันทึกค่า .env เรียบร้อย"
}

countdown_reboot() {
  info "ระบบจะ reboot ภายใน 10 วินาที"
  for remaining in 10 9 8 7 6 5 4 3 2 1; do
    printf '\r\033[1;33m[WARN]\033[0m  reboot ใน %2d วินาที...' "$remaining"
    sleep 1
  done
  printf '\n'
  sync
  systemctl reboot --no-wall || reboot -f
  exit 0
}

uninstall_app() {
  confirm_numeric "ถอนการติดตั้งระบบ" 2

  local legacy_dir=""
  local db_file="${DB_PATH:-}"
  local project_parent=""
  project_parent="$(dirname "$PROJECT_DIR")"
  legacy_dir="${project_parent}/Discord-shop3x"

  info "หยุด service และลบ unit file"
  systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload

  info "ลบคำสั่ง menubot และไฟล์ตั้งค่า"
  rm -f /usr/local/bin/menubot /etc/menubot.conf

  if [[ -n "$db_file" ]]; then
    info "ลบฐานข้อมูล SQLite: ${db_file}"
    rm -f "$db_file"
  fi

  if [[ -d "$PROJECT_DIR" ]]; then
    info "ลบโฟลเดอร์โปรเจกต์: ${PROJECT_DIR}"
    rm -rf "$PROJECT_DIR"
  fi

  if [[ -n "$legacy_dir" && "$legacy_dir" != "$PROJECT_DIR" && -d "$legacy_dir" ]]; then
    info "ลบโฟลเดอร์ดาวน์โหลดเดิม: ${legacy_dir}"
    rm -rf "$legacy_dir"
  fi

  info "ถอนการติดตั้งและลบไฟล์ที่ดาวน์โหลด/สร้างทั้งหมดเรียบร้อย"
  cd "$HOME" 2>/dev/null || true
  countdown_reboot
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
1) ถอนการติดตั้ง (ลบทุกอย่างที่ดาวน์โหลดมา)
2) ดูสถานะการทำงาน
3) รีสตาร์ทระบบ (ข้อมูลฐานข้อมูลไม่หาย)
4) ล้างข้อมูลทั้งหมดในฐานข้อมูล
5) อัปเดตสคริประบบ
6) ตั้งค่า .env
0) ออก
EOF_MENU
  read -r -p "เลือกเมนู: " choice
  case "$choice" in
    1) uninstall_app ;;
    2) show_status ;;
    3) restart_service ;;
    4) clear_database ;;
    5) update_script ;;
    6) edit_env ;;
    0) exit 0 ;;
    *) warn "เลือกไม่ถูกต้อง" ;;
  esac
  echo
done
