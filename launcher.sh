#!/bin/bash

# 1. Load the config
source /root/kiosk.conf

CHECK_INTERVAL=2

clear
tput civis # Hide cursor

echo "  [ LOADING SYSTEM ]"
echo "  ------------------"

while true; do
  # --- CHECK IF IT IS A WEBSITE ---
  if [[ "$TARGET_URL" == http* ]]; then
    if curl -sL --head --request GET "$TARGET_URL" | grep "200 OK" > /dev/null; then
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

tput cnorm # Show cursor again
/usr/bin/startx /root/kiosk.sh
