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
