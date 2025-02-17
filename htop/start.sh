#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tmux send-keys -t nodewatch:0.4 Escape
psearch="(bitcoin-qt|bitcoind|tor|i2pd|electrs|cjdroute)"
pids=$(pgrep -d',' $psearch)
( while true; do
    sleep 60s
    pnewids=$(pgrep -d',' $psearch)
    [ "$pids" != "$pnewids" ] && tmux respawn-pane -k -t nodewatch:0.4
done ) &

num_cores=$(nproc)
[ "$num_cores" -gt 8 ] && cpus_config="AllCPUs8"
[ "$num_cores" -le 8 ] && cpus_config="AllCPUs4"
[ "$num_cores" -le 4 ] && cpus_config="AllCPUs2"
[ "$num_cores" -le 2 ] && cpus_config="AllCPUs"
columns="$cpus_config"

mem_config="Memory"
swapon --show | grep -q . && mem_config+="Swap"
columns+=" $mem_config"

param="column_meters_0="
sed -i "s/^$param.*/$param$columns/" "$SCRIPT_DIR/htop.conf"

HTOPRC="$SCRIPT_DIR/htop.conf" htop -p $pids --readonly
