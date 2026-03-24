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

focus_and_navigate_chromium() {
  local target="$1"
  local win_id

  win_id=$(xdotool search --onlyvisible --class chromium 2>/dev/null | head -n1)
  [ -n "$win_id" ] || return 1

  xdotool windowactivate --sync "$win_id"
  xdotool key --window "$win_id" ctrl+l
  xdotool type --delay 1 --window "$win_id" -- "$target"
  xdotool key --window "$win_id" Return
  return 0
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
      if focus_and_navigate_chromium "$NEW_TARGET"; then
        CURRENT_TARGET="$NEW_TARGET"
        echo "Switched target to: $CURRENT_TARGET"
      fi
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
