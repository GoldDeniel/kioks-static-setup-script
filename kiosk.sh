#!/bin/bash

# 1. LOAD CONFIG
source /root/kiosk.conf

export DISPLAY=:0

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
  done
) &

# 5. Clean up Chromium state
mkdir -p /root/.config/chromium/Default/
sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /root/.config/chromium/Default/Preferences 2>/dev/null
sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' /root/.config/chromium/Default/Preferences 2>/dev/null

# 6. Launch Chromium using the variable from the config file
chromium --no-sandbox \
         --user-data-dir=/root/chrome-temp \
         --noerrdialogs \
         --disable-infobars \
         --kiosk \
         "$TARGET_URL"
