#!/bin/bash

# 1. Load the config
source /opt/kiosk/kiosk.conf

read_target_source() {
  [ -f "$SOURCE_FILE" ] || return 1

  local source_line
  source_line=$(sed -n '/[^[:space:]]/{p;q;}' "$SOURCE_FILE" 2>/dev/null)
  source_line=${source_line%%$'\r'}

  [ -n "$source_line" ] || return 1
  printf '%s' "$source_line"
}

CHECK_INTERVAL=${CHECK_INTERVAL:-2}

clear
[ -t 1 ] && tput civis # Hide cursor

echo "  [ LOADING SYSTEM ]"
echo "  ------------------"

while true; do
  TARGET_URL=$(read_target_source)

  if [ -z "$TARGET_URL" ]; then
    printf "\r  [ STATUS ]: Waiting for source file: %s...   " "$SOURCE_FILE"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  # --- CHECK IF IT IS A WEBSITE ---
  if [[ "$TARGET_URL" == http://* || "$TARGET_URL" == https://* ]]; then
    HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$TARGET_URL" 2>/dev/null || true)

    if [[ "$HTTP_CODE" =~ ^[23][0-9][0-9]$ ]]; then
      echo "  [ STATUS ]: Website Reachable! Launching..."
      break
    else
      printf "\r  [ STATUS ]: Waiting for Network: $TARGET_URL...   "
    fi

  # --- CHECK IF IT IS A LOCAL FILE ---
  else
    # Strip "file://" from the start of the string to get the real path
    CLEAN_PATH=${TARGET_URL#file://}
    
    if [ -f "$CLEAN_PATH" ]; then
      echo "  [ STATUS ]: Local File Found! Launching..."
      break
    else
      printf "\r  [ STATUS ]: Waiting for File: $CLEAN_PATH...   "
    fi
  fi

  sleep $CHECK_INTERVAL
done

[ -t 1 ] && tput cnorm # Show cursor again
/usr/bin/startx /opt/kiosk/kiosk.sh
