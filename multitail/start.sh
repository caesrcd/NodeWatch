#!/usr/bin/env sh

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tail -n 20 -f "$1" | while IFS= read -r line; do
    timestamps=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z')
    for timestamp in $timestamps; do
        local_time=$(date -d "${timestamp%Z} UTC" '+%Y-%m-%dT%H:%M:%SGMT%:::z')
        line=$(printf '%s\n' "$line" | sed "s~$timestamp~$local_time~g")
    done
    echo "$line"
done | multitail --config "$SCRIPT_DIR/config" -D -cS bitcoin -j
