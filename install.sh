#!/usr/bin/env bash
# =============================================================================
# Installer 1 baris — VPS Ubuntu/Debian kosongan -> pipeline jalan 24/7.
#
# Install (public, tanpa token — ambil release terbaru):
#
#   curl -fsSL https://raw.githubusercontent.com/onnayokheng/metapee-releases/main/install.sh | sudo bash
#
# Mode developer (repo source private, butuh fine-grained PAT Contents:Read-only):
#
#    GH_PAT='github_pat_XXXX'; curl -fsSL -H "Authorization: Bearer $GH_PAT" \
#      -H "Accept: application/vnd.github.raw" \
#      "https://api.github.com/repos/onnayokheng/metapee-affiliate/contents/install.sh?ref=main" \
#      | sudo bash -s -- --pat "$GH_PAT"
#
# Yang dipasang:
#   - python3 + venv + Pillow, ffmpeg, git          (inti pipeline)
#   - systemd service `metapee-affiliate`           (daemon auto-start/restart)
#   - Google Chrome + Xvfb + openbox + noVNC        (Tampermonkey 24/7 di VPS)
#   - Tampermonkey auto-install via Chrome policy
#   - CLI `metapee` (menu manajemen + update)
#
# Re-run perintah yang sama = update (idempotent). .env, pipeline.db, uploads/,
# tracking.csv, profil Chrome (login Shopee), dan password VNC dipertahankan.
#
# Non-interaktif: tambah --telegram-token "123:ABC" --telegram-ids "111" --port 8737
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/onnayokheng/metapee-affiliate.git"
RELEASE_TGZ="https://github.com/onnayokheng/metapee-releases/releases/latest/download/metapee.tar.gz"
BRANCH="main"
APP_DIR="/opt/metapee-affiliate"
SERVICE="metapee-affiliate"
DEF_PORT="8737"
NOVNC_PORT="6080"
DESKTOP_USER="desktop"
DISP=":99"

C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_0='\033[0m'
info() { echo -e "${C_G}[install]${C_0} $*"; }
warn() { echo -e "${C_Y}[warn]${C_0} $*"; }
die()  { echo -e "${C_R}[error]${C_0} $*" >&2; exit 1; }

# ---------- parse arg / env ----------
PAT="${GH_PAT:-}"
TG_TOKEN="${TELEGRAM_TOKEN:-}"
PORT="${HTTP_PORT:-}"
TG_IDS="${ALLOWED_TG_IDS:-}"
M_TOKEN="${META_TOKEN:-}"
M_ACCOUNT="${META_AD_ACCOUNT:-}"
M_PAGE="${META_PAGE_ID:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pat)             PAT="$2"; shift 2 ;;
    --telegram-token)  TG_TOKEN="$2"; shift 2 ;;
    --telegram-ids)    TG_IDS="$2"; shift 2 ;;
    --port)            PORT="$2"; shift 2 ;;
    --meta-token)      M_TOKEN="$2"; shift 2 ;;
    --meta-ad-account) M_ACCOUNT="$2"; shift 2 ;;
    --meta-page-id)    M_PAGE="$2"; shift 2 ;;
    *) die "Argumen tidak dikenal: $1" ;;
  esac
done

# ---------- guard ----------
[[ $EUID -eq 0 ]] || die "Jalankan dengan sudo/root."
[[ -r /etc/os-release ]] || die "Tidak bisa deteksi OS."
. /etc/os-release
[[ "$ID" =~ ^(ubuntu|debian)$ || "${ID_LIKE:-}" == *debian* ]] \
  || die "Hanya support Ubuntu/Debian (terdeteksi: $ID)."
command -v apt-get >/dev/null || die "apt-get tidak ada."
[[ "$(dpkg --print-architecture)" == "amd64" ]] \
  || die "Butuh VPS amd64 (Google Chrome tidak tersedia untuk ARM)."
ram_mb=$(free -m | awk '/^Mem:/{print $2}')
[[ "$ram_mb" -lt 1800 ]] && warn "RAM ${ram_mb}MB — Chrome butuh idealnya >=2GB, bisa lemot/OOM."

# Prompt interaktif tetap jalan di bawah `curl | bash` lewat /dev/tty.
have_tty=0; [[ -e /dev/tty ]] && have_tty=1
ask()  { local v; read -rp  "$1" v < /dev/tty; echo "$v"; }
asks() { local v; read -rsp "$1" v < /dev/tty; echo >/dev/tty; echo "$v"; }

# ---------- paket sistem ----------
info "Install paket sistem (python3, ffmpeg, git, Xvfb, noVNC, dll)..."
export DEBIAN_FRONTEND=noninteractive
# Tunggu lock apt sampai 600s (VPS baru sering sibuk unattended-upgrades saat boot).
APT="apt-get -o DPkg::Lock::Timeout=600"
$APT update -qq
$APT install -y -qq python3 python3-venv python3-pip ffmpeg git curl \
  ca-certificates openssl xvfb x11vnc novnc websockify openbox xterm

# ---------- timezone ----------
timedatectl set-timezone Asia/Jakarta 2>/dev/null || true

# ---------- Google Chrome ----------
if ! command -v google-chrome >/dev/null; then
  info "Install Google Chrome..."
  deb=$(mktemp /tmp/chrome-XXXX.deb)
  curl -fsSL -o "$deb" \
    "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
  $APT install -y -qq "$deb"
  rm -f "$deb"
else
  info "Google Chrome sudah ada — skip."
fi

# ---------- Tampermonkey auto-install (Chrome managed policy) ----------
mkdir -p /etc/opt/chrome/policies/managed
cat > /etc/opt/chrome/policies/managed/tampermonkey.json <<'EOF'
{
  "ExtensionInstallForcelist": [
    "dhdgffkkebhmkfjojejmpbldmpobfkfo;https://clients2.google.com/service/update2/crx"
  ]
}
EOF

# ---------- user desktop (Chrome menolak jalan sebagai root) ----------
id -u "$DESKTOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DESKTOP_USER"

# ---------- ambil kode: git (developer, --pat/deploy key) atau release (public) ----------
if [[ -d "$APP_DIR/.git" ]]; then
  # Server developer (git mode) — update via fetch.
  info "Repo git sudah ada — update ke $BRANCH terbaru..."
  cur_url=$(git -C "$APP_DIR" remote get-url origin)
  [[ -n "$PAT" && "$cur_url" == https://* ]] && git -C "$APP_DIR" remote set-url origin \
    "https://x-access-token:${PAT}@github.com/onnayokheng/metapee-affiliate.git"
  tmp=$(mktemp -d)
  [[ -f "$APP_DIR/tracking.csv" ]] && cp -a "$APP_DIR/tracking.csv" "$tmp/"
  git -C "$APP_DIR" fetch origin "$BRANCH" \
    || die "Fetch gagal — repo private. Re-run dengan --pat, atau pasang deploy key."
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"   # tanpa clean: .env/db/uploads aman
  [[ -f "$tmp/tracking.csv" ]] && cp -a "$tmp/tracking.csv" "$APP_DIR/tracking.csv"
  rm -rf "$tmp"
elif [[ -n "$PAT" ]]; then
  # Mode developer: clone repo source private, PAT read-only tersimpan di remote
  # (root-only server, single repo) supaya `metapee update` jalan.
  info "Clone repo source (mode developer) ke $APP_DIR..."
  git clone --branch "$BRANCH" \
    "https://x-access-token:${PAT}@github.com/onnayokheng/metapee-affiliate.git" "$APP_DIR" \
    || die "Clone gagal — PAT salah/expired?"
else
  # Mode public: ambil tarball release terbaru (tanpa token).
  info "Download release terbaru..."
  tgz=$(mktemp /tmp/metapee-rel-XXXX.tar.gz)
  curl -fsSL -o "$tgz" "$RELEASE_TGZ" \
    || die "Download release gagal — cek koneksi / rilis belum ada."
  mkdir -p "$APP_DIR"
  tar -xzf "$tgz" -C "$APP_DIR"
  rm -f "$tgz"
  info "Versi terpasang: $(cat "$APP_DIR/VERSION" 2>/dev/null || echo '?')"
fi

# ---------- venv + Pillow ----------
[[ -x "$APP_DIR/.venv/bin/python3" ]] || python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install -q --upgrade pip pillow

# ---------- .env (hanya first run — tidak pernah ditimpa) ----------
if [[ -f "$APP_DIR/.env" ]]; then
  info "Existing .env dipertahankan (edit manual + systemctl restart $SERVICE kalau mau ubah)."
  PORT=$(grep -E '^HTTP_PORT=' "$APP_DIR/.env" | cut -d= -f2 | tr -d ' ' || true)
  PORT="${PORT:-$DEF_PORT}"
else
  if [[ -z "$TG_TOKEN" && $have_tty -eq 0 ]]; then
    die "TELEGRAM_TOKEN wajib. Jalankan ulang: ... | sudo bash -s -- --telegram-token \"123:ABC\" --telegram-ids \"111,222\""
  fi
  while [[ -z "$TG_TOKEN" ]]; do
    TG_TOKEN=$(ask "TELEGRAM_TOKEN (dari @BotFather, wajib): ")
  done
  if ! curl -fsS --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null | grep -q '"ok":true'; then
    warn "getMe gagal — token Telegram mungkin salah. Lanjut, tapi cek kalau service gagal start."
  fi
  if [[ -z "$TG_IDS" && $have_tty -eq 1 ]]; then
    echo "  (ID Telegram-mu bisa dilihat dari bot @userinfobot. Boleh >1, pisah koma.)" >/dev/tty
    while [[ -z "$TG_IDS" ]]; do
      TG_IDS=$(ask "ALLOWED_TG_IDS (user id yg boleh pakai, wajib min 1): ")
    done
  fi
  [[ -z "$TG_IDS" ]] && warn "ALLOWED_TG_IDS kosong = SIAPA PUN bisa pakai bot. Set nanti di .env kalau perlu."
  if [[ $have_tty -eq 1 ]]; then
    [[ -z "$M_ACCOUNT" ]] && M_ACCOUNT=$(ask  "META_AD_ACCOUNT (Enter = skip): ")
    [[ -z "$M_PAGE"    ]] && M_PAGE=$(ask     "META_PAGE_ID    (Enter = skip): ")
    [[ -z "$M_TOKEN"   ]] && M_TOKEN=$(asks   "META_TOKEN      (Enter = skip, input tersembunyi): ")
    [[ -z "$PORT"      ]] && PORT=$(ask       "Port dashboard  (Enter = $DEF_PORT): ")
  fi
  PORT="${PORT:-$DEF_PORT}"
  {
    echo "TELEGRAM_TOKEN=$TG_TOKEN"
    echo "ALLOWED_TG_IDS=$TG_IDS"
    echo "HTTP_HOST=0.0.0.0"
    echo "HTTP_PORT=$PORT"
    [[ -n "$M_ACCOUNT" ]] && echo "META_AD_ACCOUNT=$M_ACCOUNT"
    [[ -n "$M_PAGE"    ]] && echo "META_PAGE_ID=$M_PAGE"
    [[ -n "$M_TOKEN"   ]] && echo "META_TOKEN=$M_TOKEN"
    true
  } > "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  info ".env dibuat (chmod 600)."
fi

# ---------- systemd: daemon ----------
cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Metapee affiliate daemon (Telegram + dashboard + render worker)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/.venv/bin/python3 $APP_DIR/pipeline/daemon.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# ---------- systemd: stack desktop (Xvfb + openbox + Chrome + VNC + noVNC) ----------
cat > /etc/systemd/system/vf-xvfb.service <<EOF
[Unit]
Description=Xvfb virtual display untuk Chrome

[Service]
User=$DESKTOP_USER
ExecStart=/usr/bin/Xvfb $DISP -screen 0 1280x800x24
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vf-openbox.service <<EOF
[Unit]
Description=Openbox window manager
After=vf-xvfb.service
Requires=vf-xvfb.service

[Service]
User=$DESKTOP_USER
Environment=DISPLAY=$DISP
Environment=HOME=/home/$DESKTOP_USER
ExecStart=/usr/bin/openbox
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vf-chrome.service <<EOF
[Unit]
Description=Google Chrome (Tampermonkey + Shopee affiliate, 24/7)
After=vf-openbox.service
Requires=vf-xvfb.service

[Service]
User=$DESKTOP_USER
Environment=DISPLAY=$DISP
Environment=HOME=/home/$DESKTOP_USER
ExecStart=/usr/bin/google-chrome --no-first-run --no-default-browser-check \
  --disable-gpu --window-size=1280,800 --window-position=0,0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vf-x11vnc.service <<EOF
[Unit]
Description=x11vnc (VNC server display $DISP, localhost only)
After=vf-xvfb.service
Requires=vf-xvfb.service

[Service]
User=$DESKTOP_USER
ExecStart=/usr/bin/x11vnc -display $DISP -rfbauth /home/$DESKTOP_USER/.vncpass \
  -forever -shared -localhost -rfbport 5900
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vf-novnc.service <<EOF
[Unit]
Description=noVNC (akses desktop VPS via browser, port $NOVNC_PORT)
After=vf-x11vnc.service

[Service]
User=$DESKTOP_USER
ExecStart=/usr/bin/websockify --web=/usr/share/novnc $NOVNC_PORT localhost:5900
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# ---------- CLI `metapee` (menu manajemen) ----------
cat > /usr/local/bin/metapee <<EOF
#!/bin/sh
exec sudo bash "$APP_DIR/metapee.sh" "\$@"
EOF
chmod +x /usr/local/bin/metapee
rm -f /usr/local/bin/metapee-update   # alias lama, diganti `metapee update`

# ---------- password VNC (first run only) ----------
if [[ ! -f "/home/$DESKTOP_USER/.vncpass" ]]; then
  VNC_PASS=$(openssl rand -hex 4)
  x11vnc -storepasswd "$VNC_PASS" "/home/$DESKTOP_USER/.vncpass" >/dev/null 2>&1
  chown "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER/.vncpass"
  chmod 600 "/home/$DESKTOP_USER/.vncpass"
  echo "$VNC_PASS" > /root/vnc-password.txt
  chmod 600 /root/vnc-password.txt
fi
VNC_PASS=$(cat /root/vnc-password.txt 2>/dev/null || echo "(lihat /root/vnc-password.txt)")

# ---------- firewall ----------
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$PORT/tcp"  >/dev/null || true
  ufw allow "$NOVNC_PORT/tcp" >/dev/null || true
  info "ufw: port $PORT & $NOVNC_PORT dibuka."
fi

# ---------- start semua service ----------
info "Start service..."
systemctl daemon-reload
systemctl enable -q "$SERVICE" vf-xvfb vf-openbox vf-chrome vf-x11vnc vf-novnc
systemctl restart vf-xvfb vf-openbox vf-chrome vf-x11vnc vf-novnc || true
systemctl restart "$SERVICE"
sleep 3
if ! systemctl is-active --quiet "$SERVICE"; then
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  die "Service $SERVICE gagal start — cek log di atas (token Telegram salah?)."
fi
for u in vf-xvfb vf-openbox vf-chrome vf-x11vnc vf-novnc; do
  systemctl is-active --quiet "$u" || warn "Unit $u belum aktif — cek: journalctl -u $u"
done

# ---------- ringkasan ----------
PUB_IP=$(curl -fsS4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
cat <<EOF

============================================================
  SELESAI — semua jalan 24/7
============================================================
  Dashboard   : http://$PUB_IP:$PORT/
  Desktop VPS : http://$PUB_IP:$NOVNC_PORT/vnc.html
  Password VNC: $VNC_PASS   (tersimpan: /root/vnc-password.txt)

  PENTING: buka juga port $PORT & $NOVNC_PORT di firewall/security
  group CLOUD PROVIDER (DigitalOcean/AWS/dll) — ufw saja tidak cukup.

  Langkah manual SEKALI via Desktop VPS (noVNC):
   1. Buka http://$PUB_IP:$NOVNC_PORT/vnc.html, masukkan password VNC.
      Chrome sudah jalan, Tampermonkey terpasang otomatis.
   2. Kalau Chrome minta: aktifkan toggle "Allow User Scripts" untuk
      Tampermonkey di chrome://extensions.
   3. Buka http://127.0.0.1:$PORT/script.js
      -> Tampermonkey menawarkan Install -> klik Install.
   4. Login affiliate.shopee.co.id (sesi tersimpan permanen).

  Kalau daemon masih jalan di laptop: MATIKAN (2 poller Telegram
  dengan token sama = konflik 409).

  Semua manajemen lewat SATU command:
    metapee                          # menu interaktif
    metapee status | update | token | ids | meta | logs | help
============================================================
EOF
