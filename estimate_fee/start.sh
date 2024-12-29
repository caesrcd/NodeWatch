#!/usr/bin/env bash

forecast_type=$1
if [ "$forecast_type" == "auto" ]; then
    forecast_type=$(shuf -e "smart" "median" "mempool" -n 1)
elif [ -z "$forecast_type" ]; then
    forecast_type="smart"
fi

convert_to_sat() {
    local fee="$1"
    fee=$(awk -v fee="$fee" 'BEGIN {printf "%.8f", fee}')
    fee=$(echo "$fee * 100000" | bc)
    fee=$(round_up "$fee")
    echo "${fee} sat/vB"
}

math_max() {
    local max="$1"
    for num in "$@"; do
        max=$(echo -e "$max\n$num" | awk '{if ($1 > max) max=$1} END {print max}')
    done
    echo "$max"
}

math_min() {
    local min="$1"
    for num in "$@"; do
        min=$(echo -e "$min\n$num" | awk -v min="$min" '{if ($1 < min) min=$1} END {print min}')
    done
    echo "$min"
}

round_up() {
    local number="$1"
    if [[ "$number" =~ ^-?[0-9]+$ ]]; then
        echo "$number"
    else
        echo "$number" | awk '{print int($1) + ($1 > int($1))}'
    fi
}

mempoolinfo=$(bitcoin-cli -rpcwait getmempoolinfo)
mempool_loaded=$(echo "$mempoolinfo" | jq -r '.loaded')
if [ "$mempool_loaded" == "false" -o "$forecast_type" == "smart" ]; then
    firstblk=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq .feerate)
    secondblk=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq .feerate)
    thirdblk=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq .feerate)
    laterblk=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq .feerate)
elif [ "$forecast_type" == "median" ]; then
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

    minimum_fee=$(echo "$mempoolinfo" | jq -r '.mempoolminfee')
    fees=$(echo "$fees" | awk '{$1=$1};1')
    medianfee=$(echo "$fees" | cut -d' ' -f1)
    firstblk=$(math_max "$minimum_fee" "$medianfee")
    medianfee=$(echo "$fees" | awk '{print ($1 + $2) / 2}')
    secondblk=$(math_max "$minimum_fee" "$medianfee")
    medianfee=$(echo "$secondblk $fees" | awk '{print ($1 + $4) / 2}')
    thirdblk=$(math_max "$minimum_fee" "$medianfee")
    minfee2x=$(echo "$minimum_fee" | awk '{print $1 * 2}')
    medianfee=$(echo "$thirdblk $fees" | awk '{print ($1 + $5) / 2}')
    economyfee=$(math_min "$medianfee" "$thirdblk")
    laterblk=$(math_max "$minimum_fee" "$economyfee")

    firstblk=$(math_max $firstblk $secondblk $thirdblk $laterblk)
    secondblk=$(math_max $secondblk $thirdblk $laterblk)
    thirdblk=$(math_max $thirdblk $laterblk)
elif [ "$forecast_type" == "mempool" ]; then
    fees_recommended=$(curl -s "https://mempool.space/api/v1/fees/recommended")
    if [ -z "$fees_recommended" ]; then
        echo "Error: Failed to retrieve data from the API."
        exit 1
    fi
    firstblk=$(echo "$fees_recommended" | jq -r '.fastestFee' | awk '{print $1 / 100000}')
    secondblk=$(echo "$fees_recommended" | jq -r '.halfHourFee' | awk '{print $1 / 100000}')
    thirdblk=$(echo "$fees_recommended" | jq -r '.hourFee' | awk '{print $1 / 100000}')
    laterblk=$(echo "$fees_recommended" | jq -r '.economyFee' | awk '{print $1 / 100000}')
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
