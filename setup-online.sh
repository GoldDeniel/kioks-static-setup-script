#!/bin/bash

set -euo pipefail

INSTALL_DIR="/opt/kiosk"
SITE_DIR="$INSTALL_DIR/site"
SERVICE_TARGET="/etc/systemd/system/kiosk.service"
SMB_CONF="/etc/samba/smb.conf"

if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root (sudo bash <(wget -qO- https://your-domain/setup-online.sh))"
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "Cannot detect Linux distribution (/etc/os-release missing)."
  exit 1
fi

source /etc/os-release

install_packages() {
  case "${ID:-}" in
    debian|ubuntu|raspbian)
      apt-get update
      # On Ubuntu, chromium is often a snap, but for kiosk we prefer the deb if available or chromium-browser
      apt-get install xinit xserver-xorg x11-xserver-utils openbox xdotool curl samba -y
      if ! apt-get install chromium -y 2>/dev/null; then
          apt-get install chromium-browser -y || echo "Warning: Could not install chromium via apt. Please install it manually."
      fi
      ;;
    fedora)
      dnf install xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-utils openbox chromium xdotool curl samba -y
      ;;
    arch)
      pacman -S --noconfirm xorg-server xorg-xinit openbox chromium xdotool curl samba
      ;;
    *)
      if [[ "${ID_LIKE:-}" == *"debian"* ]]; then
        apt-get update
        apt-get install xinit xserver-xorg x11-xserver-utils openbox xdotool curl samba -y
        apt-get install chromium -y || apt-get install chromium-browser -y || true
      elif [[ "${ID_LIKE:-}" == *"fedora"* || "${ID_LIKE:-}" == *"rhel"* ]]; then
        dnf install xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-utils openbox chromium xdotool curl samba -y
      elif [[ "${ID_LIKE:-}" == *"arch"* ]]; then
        pacman -S --noconfirm xorg-server xorg-xinit openbox chromium xdotool curl samba
      else
        echo "Unsupported distribution: ${ID:-unknown}"
        exit 1
      fi
      ;;
  esac
}

configure_samba_share() {
  mkdir -p /etc/samba

  if [ -f "$SMB_CONF" ] && ! grep -q "kiosk-site share" "$SMB_CONF"; then
    cp "$SMB_CONF" "${SMB_CONF}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  if [ ! -f "$SMB_CONF" ]; then
    cat > "$SMB_CONF" <<'EOF_SAMBA_GLOBAL'
[global]
   workgroup = WORKGROUP
   map to guest = Bad User
   server role = standalone server
   usershare allow guests = yes
EOF_SAMBA_GLOBAL
  elif ! grep -q "map to guest = Bad User" "$SMB_CONF"; then
    sed -i '/^\[global\]/a\   map to guest = Bad User' "$SMB_CONF"
  fi

  if ! grep -q "kiosk-site share" "$SMB_CONF"; then
    cat >> "$SMB_CONF" <<'EOF_SAMBA_SHARE'

### kiosk-site share ###
[kiosk-site]
   comment = Kiosk content share
   path = /opt/kiosk/site
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0666
   directory mask = 0777
   force user = root
EOF_SAMBA_SHARE
  fi

  chmod -R 0777 "$SITE_DIR"

  systemctl enable --now smbd.service 2>/dev/null || true
  systemctl enable --now nmbd.service 2>/dev/null || true
  systemctl enable --now smb.service 2>/dev/null || true
  systemctl enable --now nmb.service 2>/dev/null || true
}

echo "Installing required packages..."
install_packages

echo "Deploying kiosk project to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR" "$SITE_DIR"

cat > "$INSTALL_DIR/kiosk.conf" <<'EOF_KIOSK_CONF'
# Text file that contains the target source (URL or file:// path)
SOURCE_FILE="/opt/kiosk/site/source-001.txt"

# How often to refresh the page (in seconds)
REFRESH_TIME=30

# How often launcher checks source/file readiness (in seconds)
CHECK_INTERVAL=2

# How often to check for changes in the source file (in seconds)
SOURCE_POLL_INTERVAL=3
EOF_KIOSK_CONF
chmod 0644 "$INSTALL_DIR/kiosk.conf"

cat > "$INSTALL_DIR/kiosk.service" <<'EOF_KIOSK_SERVICE'
[Unit]
Description=Kiosk Launcher Service
After=network-online.target
Wants=network-online.target
# This line tells the system to stop the login prompt on tty1
Conflicts=getty@tty1.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kiosk
ExecStart=/opt/kiosk/launcher.sh
Restart=always

# Force the script to own the physical screen
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
# These ensure the screen is cleared and ready for your message
ExecStartPre=-/usr/bin/tput civis
ExecStopPost=-/usr/bin/tput cnorm

[Install]
WantedBy=multi-user.target
EOF_KIOSK_SERVICE
chmod 0644 "$INSTALL_DIR/kiosk.service"

cat > "$INSTALL_DIR/launcher.sh" <<'EOF_LAUNCHER_SH'
#!/bin/bash

source /opt/kiosk/kiosk.conf

read_target_source() {
  [ -f "$SOURCE_FILE" ] || return 1
  local source_line
  source_line=$(sed -n '/[^[:space:]]/{p;q;}' "$SOURCE_FILE" 2>/dev/null)
  source_line=${source_line%%$'\r'}
  [ -n "$source_line" ] || return 1
  printf '%s' "$source_line"
}

target_available() {
  local target="$1"
  local http_code
  local clean_path

  if [[ "$target" == http://* || "$target" == https://* ]]; then
    http_code=$(curl -sL -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$target" 2>/dev/null || true)
    [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]
  else
    clean_path=${target#file://}
    [ -f "$clean_path" ]
  fi
}

wait_for_valid_target() {
  local target
  while true; do
    target=$(read_target_source)
    if [ -z "$target" ]; then
      printf "\r  [ STATUS ]: Waiting for source file: %s...   " "$SOURCE_FILE"
      sleep "${CHECK_INTERVAL:-2}"
      continue
    fi

    if target_available "$target"; then
      echo "  [ STATUS ]: Target available: $target"
      return 0
    fi

    if [[ "$target" == http://* || "$target" == https://* ]]; then
      printf "\r  [ STATUS ]: Waiting for Network: %s...   " "$target"
    else
      printf "\r  [ STATUS ]: Waiting for File: %s...   " "${target#file://}"
    fi
    sleep "${CHECK_INTERVAL:-2}"
  done
}

clear
[ -t 1 ] && tput civis
echo "  [ LOADING SYSTEM ]"
echo "  ------------------"

while true; do
  wait_for_valid_target
  /usr/bin/startx /opt/kiosk/kiosk.sh
  echo "  [ STATUS ]: X session ended. Restarting..."
  sleep 1
done
EOF_LAUNCHER_SH
chmod 0755 "$INSTALL_DIR/launcher.sh"

cat > "$INSTALL_DIR/kiosk.sh" <<'EOF_KIOSK_SH'
#!/bin/bash

source /opt/kiosk/kiosk.conf

read_target_source() {
  [ -f "$SOURCE_FILE" ] || return 1
  local source_line
  source_line=$(sed -n '/[^[:space:]]/{p;q;}' "$SOURCE_FILE" 2>/dev/null)
  source_line=${source_line%%$'\r'}
  [ -n "$source_line" ] || return 1
  printf '%s' "$source_line"
}

target_available() {
  local target="$1"
  local http_code
  local clean_path

  if [[ "$target" == http://* || "$target" == https://* ]]; then
    http_code=$(curl -sL -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$target" 2>/dev/null || true)
    [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]
  else
    clean_path=${target#file://}
    [ -f "$clean_path" ]
  fi
}

TARGET_URL=$(read_target_source)

if [ -z "$TARGET_URL" ]; then
  echo "No target source found in $SOURCE_FILE"
  exit 1
fi

if ! target_available "$TARGET_URL"; then
  echo "Initial target is not reachable: $TARGET_URL"
  exit 1
fi

export DISPLAY=:0

xset s off
xset s noblank
xset -dpms

openbox-session &
OPENBOX_PID=$!

(
  while true; do
    sleep "${REFRESH_TIME:-300}"
    xdotool key F5
  done
) &
REFRESH_PID=$!

mkdir -p /root/.config/chromium/Default/
sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /root/.config/chromium/Default/Preferences 2>/dev/null
sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' /root/.config/chromium/Default/Preferences 2>/dev/null

chromium --no-sandbox \
         --user-data-dir=/opt/kiosk/chrome-temp \
         --noerrdialogs \
         --disable-infobars \
         --kiosk \
         "$TARGET_URL" &
CHROMIUM_PID=$!

CURRENT_TARGET="$TARGET_URL"
SOURCE_POLL_INTERVAL="${SOURCE_POLL_INTERVAL:-3}"

(
  while true; do
    sleep "$SOURCE_POLL_INTERVAL"

    NEW_TARGET=$(read_target_source)
    [ -n "$NEW_TARGET" ] || continue
    [ "$NEW_TARGET" = "$CURRENT_TARGET" ] && continue

    if target_available "$NEW_TARGET"; then
      echo "Detected source change to reachable target: $NEW_TARGET"
      kill "$CHROMIUM_PID" 2>/dev/null || true
      exit 0
    fi
  done
) &
WATCHER_PID=$!

cleanup() {
  kill "$WATCHER_PID" 2>/dev/null || true
  kill "$REFRESH_PID" 2>/dev/null || true
  kill "$OPENBOX_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$CHROMIUM_PID"
EOF_KIOSK_SH
chmod 0755 "$INSTALL_DIR/kiosk.sh"

cat > "$SITE_DIR/source-001.txt" <<'EOF_SOURCE_TXT'
file:///opt/kiosk/site/index.html
EOF_SOURCE_TXT
chmod 0666 "$SITE_DIR/source-001.txt"

cat > "$SITE_DIR/index.html" <<'EOF_INDEX_HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Kiosk Ready</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #0f172a;
        --card: #111827;
        --text: #e5e7eb;
        --muted: #9ca3af;
        --ok: #22c55e;
      }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: radial-gradient(circle at 20% 20%, #1d4ed8, var(--bg));
        font-family: "DejaVu Sans", sans-serif;
        color: var(--text);
      }
      .card {
        background: rgba(17, 24, 39, 0.9);
        border: 1px solid rgba(229, 231, 235, 0.15);
        border-radius: 14px;
        padding: 2rem;
        width: min(90vw, 680px);
        box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35);
      }
      h1 {
        margin-top: 0;
        margin-bottom: 0.5rem;
        font-size: clamp(1.6rem, 3vw, 2.3rem);
      }
      p {
        margin: 0.6rem 0;
        color: var(--muted);
        font-size: 1.05rem;
      }
      .status {
        color: var(--ok);
        font-weight: 700;
        letter-spacing: 0.03em;
        text-transform: uppercase;
      }
      code {
        color: #93c5fd;
      }
    </style>
  </head>
  <body>
    <section class="card">
      <h1>Kiosk Setup Complete</h1>
      <p class="status">System online</p>
      <p>Set your source in <code>/opt/kiosk/site/source-001.txt</code>.</p>
      <p>Example URL: <code>https://example.com</code></p>
      <p>Example file: <code>file:///opt/kiosk/site/index.html</code></p>
    </section>
  </body>
</html>
EOF_INDEX_HTML
chmod 0666 "$SITE_DIR/index.html"

echo "Installing and enabling systemd service..."
install -m 0644 "$INSTALL_DIR/kiosk.service" "$SERVICE_TARGET"
systemctl daemon-reload
systemctl enable kiosk.service

echo "Configuring Samba share on $SITE_DIR..."
configure_samba_share

echo "Restarting kiosk service..."
systemctl restart kiosk.service

echo "Setup complete. Share name: kiosk-site"
echo "Edit source from: $SITE_DIR/source-001.txt"

# Only reboot if not in a container/sandbox environment
if [ ! -f /.dockerenv ]; then
  read -p "Press 'R' to reboot the system (or any other key to finish): " -n 1 key </dev/tty
  echo
  if [[ "$key" == "R" || "$key" == "r" ]]; then
    reboot
  fi
fi
