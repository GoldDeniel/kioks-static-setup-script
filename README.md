# 🚀 Simple Linux Kiosk

A lightweight, robust kiosk solution designed for Raspberry Pi (Zero 2 W) and other Linux systems. This setup boots directly into a fullscreen Chromium window, handles network/file delays gracefully before launching graphics, and includes an automatic refresh loop.
#✨ Features

    Smart Launch: Waits for a URL (via curl) or a local file to be available before starting the X server.

    No-Port Solution: Runs on standard ports (80/443) or local file paths.

    Hardware Efficient: Uses openbox (a minimal window manager) to save RAM—ideal for 512MB devices.

    Auto-Refresh: Simulates an F5 keypress every X minutes to keep content fresh.

    Root-Safe: Configured to run Chromium even under root with the necessary security flags.

# 📦 Prerequisites

Ensure you have a "Lite" or "Minimal" version of your OS installed (no desktop environment required).
Package Installation
Debian / Ubuntu / Raspberry Pi OS
```
sudo apt update
sudo apt install xinit xserver-xorg x11-xserver-utils openbox chromium-browser xdotool curl -y
```
Fedora
```
sudo dnf install xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-utils openbox chromium xdotool curl -y
```
Arch Linux
```
sudo pacman -S xorg-server xorg-xinit openbox chromium xdotool curl
```
# 📂 File Structure & Placement
File	Destination	Description
kiosk.conf	/root/kiosk.conf	Main Config: Edit your URL and refresh time here.
launcher.sh	/root/launcher.sh	The Waiter: Checks for network/file before starting X.
kiosk.sh	/root/kiosk.sh	The Engine: Launches the Window Manager and Browser.
kiosk.service	/etc/systemd/system/kiosk.service	The Manager: Handles auto-boot and recovery.
🛠️ Setup Instructions
1. Place the Scripts

Copy all scripts to the /root/ directory. Ensure they are executable:
```
chmod +x /root/launcher.sh
chmod +x /root/kiosk.sh
```
2. Configure your URL

Edit /root/kiosk.conf to point to your website or local file:
For a website:
`TARGET_URL="http://google.com"`

OR for a local file:
`TARGET_URL="file:///root/index.html"`

3. Enable the Service

Register the kiosk to start automatically on boot:
```
sudo systemctl daemon-reload
sudo systemctl enable kiosk.service
```

# ⚙️ Configuration (kiosk.conf)
Variable	Default	Description
TARGET_URL	http://...	The URL or local file:/// path to display.
REFRESH_TIME	300	How many seconds to wait before auto-refreshing (F5).
# 🖥️ How it Works

    Boot: The systemd service triggers launcher.sh.

    Waiting: The screen stays in text mode, displaying "Connecting..." until the TARGET_URL is reachable.

    Graphics: Once reachable, startx is triggered, launching kiosk.sh.

    Window Management: openbox starts in the background to ensure Chromium stays fullscreen without borders.

    Kiosk: Chromium launches in --kiosk mode with all error dialogs disabled.

    Maintenance: A background loop runs xdotool to refresh the page at the interval defined in your config.
