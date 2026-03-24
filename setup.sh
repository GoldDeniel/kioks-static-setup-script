#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_DIR="/opt/kiosk"
SITE_DIR="$INSTALL_DIR/site"
SERVICE_TARGET="/etc/systemd/system/kiosk.service"
SMB_CONF="/etc/samba/smb.conf"

if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
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
      apt update
      apt install xinit xserver-xorg x11-xserver-utils openbox chromium xdotool curl samba -y
      ;;
    fedora)
      dnf install xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-utils openbox chromium xdotool curl samba -y
      ;;
    arch)
      pacman -S --noconfirm xorg-server xorg-xinit openbox chromium xdotool curl samba
      ;;
    *)
      if [[ "${ID_LIKE:-}" == *"debian"* ]]; then
        apt update
        apt install xinit xserver-xorg x11-xserver-utils openbox chromium xdotool curl samba -y
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
    cat > "$SMB_CONF" <<'EOF'
[global]
   workgroup = WORKGROUP
   map to guest = Bad User
   server role = standalone server
   usershare allow guests = yes
EOF
  elif ! grep -q "map to guest = Bad User" "$SMB_CONF"; then
    sed -i '/^\[global\]/a\   map to guest = Bad User' "$SMB_CONF"
  fi

  if ! grep -q "kiosk-site share" "$SMB_CONF"; then
    cat >> "$SMB_CONF" <<'EOF'

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
EOF
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

install -m 0755 "$SCRIPT_DIR/launcher.sh" "$INSTALL_DIR/launcher.sh"
install -m 0755 "$SCRIPT_DIR/kiosk.sh" "$INSTALL_DIR/kiosk.sh"
install -m 0644 "$SCRIPT_DIR/kiosk.conf" "$INSTALL_DIR/kiosk.conf"
install -m 0644 "$SCRIPT_DIR/kiosk.service" "$INSTALL_DIR/kiosk.service"

if [ -f "$SCRIPT_DIR/site/source-001.txt" ]; then
  install -m 0666 "$SCRIPT_DIR/site/source-001.txt" "$SITE_DIR/source-001.txt"
elif [ ! -f "$SITE_DIR/source-001.txt" ]; then
  echo "file:///opt/kiosk/site/index.html" > "$SITE_DIR/source-001.txt"
  chmod 0666 "$SITE_DIR/source-001.txt"
fi

if [ -f "$SCRIPT_DIR/site/index.html" ] && [ ! -f "$SITE_DIR/index.html" ]; then
  install -m 0666 "$SCRIPT_DIR/site/index.html" "$SITE_DIR/index.html"
fi

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

read -p "Press Enter to reboot the system..." </dev/tty
reboot
