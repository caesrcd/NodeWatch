#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

pids=$(pgrep -d',' '(bitcoin-qt|bitcoind|tor|i2pd|electrs|cjdroute)')

HTOPRC="$SCRIPT_DIR/htop.conf" htop -p $pids
