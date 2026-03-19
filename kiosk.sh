#!/bin/bash

# --- CONFIGURATION ---
TARGET_URL="http://google.com"  # Change this to your IP or URL
CHECK_INTERVAL=2               # Seconds to wait between pings
REFRESH_TIME=300               # Seconds between F5 refreshes (5 mins)
# ---------------------

export DISPLAY=:0

# 1. NETWORK CHECK: Wait until the URL is reachable
# This stays in the terminal until the site responds with a 200 OK
clear
echo "Connecting..."
until curl -sL --head --request GET "$TARGET_URL" | grep "200 OK" > /dev/null; do
  clear
  echo "Connecting... (Waiting for $TARGET_URL)"
  sleep $CHECK_INTERVAL
done

echo "Connection established! Starting Kiosk..."

# 2. Disable screen saving
xset s off
xset s noblank
xset -dpms

# 3. Start Window Manager
openbox-session &

# 4. The Auto-Refresh Loop
(
  while true; do
    sleep $REFRESH_TIME
    xdotool key F5
    echo "Page refreshed at $(date)"
  done
) &

# 5. Clean up Chromium state
mkdir -p /root/.config/chromium/Default/
sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /root/.config/chromium/Default/Preferences 2>/dev/null
sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' /root/.config/chromium/Default/Preferences 2>/dev/null

# 6. Launch Chromium
chromium --no-sandbox \
         --user-data-dir=/root/chrome-temp \
         --noerrdialogs \
         --disable-infobars \
         --kiosk \
         --check-for-update-interval=31536000 \
         "$TARGET_URL"
