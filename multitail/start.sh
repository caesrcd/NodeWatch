#!/usr/bin/env sh

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tail -n 20 -f "$1" | while IFS= read -r line; do
    timestamp=$(expr "$line" : '\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)Z')
    if [ -n "$timestamp" ]; then
        local_time=$(date -d "${timestamp} UTC" '+%Y-%m-%dT%H:%M:%SGMT%:::z')
        echo "${line}" | sed "s~^${timestamp}Z~${local_time}~"
    else
        echo "$line"
    fi
done | multitail --config "$SCRIPT_DIR/config" -D -cS bitcoin -j
