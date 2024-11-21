#!/usr/bin/env bash

forecast_type=$1

convert_to_sat() {
    local fee="$1"
    fee=$(awk -v fee="$fee" 'BEGIN {printf "%.8f", fee}')
    fee=$(echo "$fee * 100000" | bc)
    fee=$(awk -v fee="$fee" 'BEGIN {printf "%.0f", fee}')
    echo "${fee} sat/vB"
}

mempool_loaded=$(bitcoin-cli -rpcwait getmempoolinfo | jq -r '.loaded')
if [ "$mempool_loaded" == "false" -o "$forecast_type" != "median" ]; then
    firstblk=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq .feerate)
    secondblk=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq .feerate)
    thirdblk=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq .feerate)
    laterblk=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq .feerate)
else
    tx_data=$(bitcoin-cli -rpcwait getrawmempool true | jq -c \
        'with_entries(.value |= {vsize, weight, fee: .fees.modified}) | to_entries |
        map({key, vsize: .value.vsize, weight: .value.weight, fee: .value.fee}) |
        sort_by(.fee / .vsize) | reverse')

    acc_weight=0
    tx_per_blk=0
    while IFS= read -r item; do
        weight=$(echo "$item" | jq -r '.weight')
        if ((acc_weight + weight > 450000)); then
            break
        fi
        tx_per_blk=$((tx_per_blk + 1))
        acc_weight=$((acc_weight + weight))
    done <<< "$(echo "$tx_data" | jq -c '.[]')"

    total_tx=$(echo "$tx_data" | jq 'length')
    tx_per_blk=$((tx_per_blk * 4))

    acc_blk=1
    while [ $acc_blk -le 4 ]; do
        [ $acc_blk -eq 4 ] && acc_blk=8
        median=$((tx_per_blk * acc_blk))
        if ((median > total_tx)); then
            median=$((total_tx - tx_per_blk))
            ((median < 1)) && median=1
        fi
        fee=$(echo "$tx_data" | jq --argjson median "$median" '.[$median].fee')
        vsize=$(echo "$tx_data" | jq --argjson median "$median" '.[$median].vsize')
        [ "$fee" = "" -o "$vsize" == "" ] && fee=0.00000001 vsize=1
        fees="$fees "$(echo "$fee $vsize" | awk '{print $1 / $2 * 1000}')
        acc_blk=$((acc_blk + 1))
    done

    fees=$(echo "$fees" | awk '{$1=$1};1')
    firstblk=$(echo "$fees" | cut -d' ' -f1)
    secondblk=$(echo "$fees" | cut -d' ' -f2)
    thirdblk=$(echo "$fees" | cut -d' ' -f3)
    laterblk=$(echo "$fees" | cut -d' ' -f4)
fi

firstblk=$(convert_to_sat "$firstblk")
secondblk=$(convert_to_sat "$secondblk")
thirdblk=$(convert_to_sat "$thirdblk")
laterblk=$(convert_to_sat "$laterblk")

tcols=$(tput cols)

echo -e "$(printf '%*s' $(( ($tcols - 15) / 2 )) '')Transaction Fees\n
$(printf '%*s' $(( ($tcols - 7) / 2 )) '')\033[0mBlock 1
$(printf '%*s' $(( ($tcols - ${#firstblk}) / 2 )) '')\033[35m$firstblk\n
$(printf '%*s' $(( ($tcols - 7) / 2 )) '')\033[0mBlock 2
$(printf '%*s' $(( ($tcols - ${#secondblk}) / 2 )) '')\033[35m$secondblk\n
$(printf '%*s' $(( ($tcols - 7) / 2 )) '')\033[0mBlock 3
$(printf '%*s' $(( ($tcols - ${#thirdblk}) / 2 )) '')\033[35m$thirdblk\n
$(printf '%*s' $(( ($tcols - 11) / 2 )) '')\033[0mLater block
$(printf '%*s' $(( ($tcols - ${#laterblk}) / 2 )) '')\033[35m$laterblk"
