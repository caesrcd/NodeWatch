#!/usr/bin/env bash

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tail -n 20 -f "$1" | while read -r line; do
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})Z ]]; then
        utc="${BASH_REMATCH[1]}"
        local_time=$(date -d "${utc} UTC" '+%Y-%m-%dT%H:%M:%SGMT%:::z')
        echo "${line/${utc}Z/${local_time}}"
    else
        echo "$line"
    fi
done | multitail --config "$SCRIPT_DIR/config" -D -cS bitcoin -j
