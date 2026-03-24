#!/bin/bash

# 1. LOAD CONFIG
source /opt/kiosk/kiosk.conf

read_target_source() {
  [ -f "$SOURCE_FILE" ] || return 1

  local source_line
  source_line=$(sed -n '/[^[:space:]]/{p;q;}' "$SOURCE_FILE" 2>/dev/null)
  source_line=${source_line%%$'\r'}

  [ -n "$source_line" ] || return 1
  printf '%s' "$source_line"
}

TARGET_URL=$(read_target_source)

if [ -z "$TARGET_URL" ]; then
  echo "No target source found in $SOURCE_FILE"
  exit 1
fi

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
         --user-data-dir=/opt/kiosk/chrome-temp \
         --noerrdialogs \
         --disable-infobars \
         --kiosk \
         "$TARGET_URL"
