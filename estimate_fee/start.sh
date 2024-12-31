#!/usr/bin/env bash

forecast_type=$1

# Round numbers up to the nearest integer.
math_ceil() {
    local number="$1"
    if ! [[ "$number" =~ ^-?[0-9]+$ ]]; then
        number=$(awk -v num="$number" 'BEGIN {print int(num) + (num > int(num))}')
    fi
    echo "$number"
}

# Find the maximum between two or more elements passed to it as arguments.
math_max() {
    local max="$1"
    for num in "$@"; do
        max=$(echo -e "$max\n$num" | awk '{if ($1 > max) max=$1} END {print max}')
    done
    echo "$max"
}

# Find the minimum between two or more elements passed to it as arguments.
math_min() {
    local min="$1"
    for num in "$@"; do
        min=$(echo -e "$min\n$num" | awk -v min="$min" '{if ($1 < min) min=$1} END {print min}')
    done
    echo "$min"
}

mempoolinfo=$(bitcoin-cli -rpcwait getmempoolinfo)
mempool_loaded=$(echo "$mempoolinfo" | jq -r '.loaded')
if [ "$mempool_loaded" == "true" -a "$forecast_type" == "median" ]; then
    tx_data=$(bitcoin-cli -rpcwait getrawmempool true | jq -c \
        'with_entries(.value |= {vsize, weight, fee: .fees.modified}) | to_entries |
        map({key, vsize: .value.vsize, weight: .value.weight, fee: .value.fee}) |
        sort_by(.fee / .vsize) | reverse')

    acc_weight=0
    tx_per_blk=0
    while IFS= read -r item; do
        weight=$(echo "$item" | jq -r '.weight')
        if ((acc_weight + weight >= 200000)); then
            break
        fi
        tx_per_blk=$((tx_per_blk + 1))
        acc_weight=$((acc_weight + weight))
    done <<< "$(echo "$tx_data" | jq -c '.[]')"

    total_tx=$(echo "$tx_data" | jq 'length')
    tx_per_blk=$((tx_per_blk * 5))

    acc_blk=1
    while [ $acc_blk -le 3 ]; do
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
    firstblk=$(math_max $minimum_fee $medianfee)
    medianfee=$(echo "$fees" | awk '{print ($1 + $2) / 2}')
    secondblk=$(math_max $minimum_fee $medianfee)
    medianfee=$(echo "$secondblk $fees" | awk '{print ($1 + $4) / 2}')
    thirdblk=$(math_max $minimum_fee $medianfee)
    minfee2x=$(awk -v fee="$minimum_fee" 'BEGIN {print fee * 2}')
    economyfee=$(math_min $minfee2x $thirdblk)
    laterblk=$(math_max $minimum_fee $economyfee)

    firstblk=$(math_max $firstblk $secondblk $thirdblk $laterblk)
    secondblk=$(math_max $secondblk $thirdblk $laterblk)
    thirdblk=$(math_max $thirdblk $laterblk)
elif [ "$forecast_type" == "mempool" ]; then
    fees_recommended=$(curl -s "https://mempool.space/api/v1/fees/recommended")
    if [ -z "$fees_recommended" ]; then
        echo "Error: Failed to retrieve data from the API."
        exit 1
    fi
    firstblk=$(echo "$fees_recommended" | jq -r '.fastestFee')
    secondblk=$(echo "$fees_recommended" | jq -r '.halfHourFee')
    thirdblk=$(echo "$fees_recommended" | jq -r '.hourFee')
    laterblk=$(echo "$fees_recommended" | jq -r '.economyFee')
else
    firstblk=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq .feerate)
    secondblk=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq .feerate)
    thirdblk=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq .feerate)
    laterblk=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq .feerate)
fi

if [ "$forecast_type" != "mempool" ]; then
    firstblk=$(awk -v fee="$firstblk" 'BEGIN {print fee * 100000}')
    secondblk=$(awk -v fee="$secondblk" 'BEGIN {print fee * 100000}')
    thirdblk=$(awk -v fee="$thirdblk" 'BEGIN {print fee * 100000}')
    laterblk=$(awk -v fee="$laterblk" 'BEGIN {print fee * 100000}')
fi

firstblk="$(math_ceil $firstblk) sat/vB"
secondblk="$(math_ceil $secondblk) sat/vB"
thirdblk="$(math_ceil $thirdblk) sat/vB"
laterblk="$(math_ceil $laterblk) sat/vB"

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
