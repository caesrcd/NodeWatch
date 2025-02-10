#!/usr/bin/env bash

forecast_type=$1

# Round numbers up to the nearest integer except when it is less than 1
math_round_up() {
    local number="$1"
    if ! [[ "$number" =~ ^-?[0-9]+$ ]]; then
        number=$(awk -v num="$number" 'BEGIN {
            if (num > 0.999) print int(num) + (num > int(num));
            else if (num < 0.01) print (num < 0.01 ? num : sprintf("%.3f", num));
            else if (num < 0.1) print sprintf("%.2f", num);
            else if (num < 1) print sprintf("%.1f", num);
            else print num;
        }')
    fi
    echo "$number"
}

# Find the maximum between two or more elements passed to it as arguments.
math_max() {
    local max="$1"
    for num in "$@"; do
        max=$(echo -e "$max\n$num" | awk -v max="$max" '{if ($1 >= max) max=$1} END {print max}')
    done
    echo "$max"
}

# Find the minimum between two or more elements passed to it as arguments.
math_min() {
    local min="$1"
    for num in "$@"; do
        min=$(echo -e "$min\n$num" | awk -v min="$min" '{if ($1 <= min) min=$1} END {print min}')
    done
    echo "$min"
}

mempoolinfo=$(bitcoin-cli -rpcwait getmempoolinfo)
mempool_loaded=$(echo "$mempoolinfo" | jq -r '.loaded')
if [ "$mempool_loaded" == "true" -a "$forecast_type" == "median" ]; then
    fees="[]"
    rawmempool=$(bitcoin-cli -rpcwait getrawmempool true)
    if [ "$rawmempool" != "{}" ]; then
        fees=$(echo "$rawmempool" | jq -s \
          'map(to_entries[] | {fee: (.value.fees.modified / .value.vsize * 1e8), weight: .value.weight})
          | sort_by(.fee) | reverse | reduce .[] as $tx ({"blocks": [[]], "total_weight": [0]};
              if .total_weight[-1] + $tx.weight <= 3996000 then
                  .blocks[-1] += [$tx.fee] | .total_weight[-1] += $tx.weight
              elif (.blocks | length) < 3 then
                  .blocks += [[$tx.fee]] | .total_weight += [$tx.weight]
              else .
              end)
          | .blocks[:3]
          | map(sort | if length % 2 == 1 then .[length/2 | floor] else (.[length/2 - 1] + .[length/2]) / 2 end)')
    fi

    minimum_fee=$(echo "$mempoolinfo" | jq -r '.mempoolminfee * 1e5')
    blocks=("firstblk" "secondblk" "thirdblk")
    for i in {0..2}; do
        medianfee=$(echo "$fees" | jq -r ".[${i}] // 0")
        if awk -v x="$medianfee" 'BEGIN {exit !(x != 0)}'; then
            [ -n "$prev_fee" ] && medianfee=$(echo "$prev_fee $medianfee" | awk '{print ($1 + $2) / 2}')
            prev_fee=${!blocks[i]}
        fi
        declare "${blocks[i]}"=$(math_max "$minimum_fee" "$medianfee")
    done

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
    firstblk=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq '.feerate * 1e5')
    secondblk=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq '.feerate * 1e5')
    thirdblk=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq '.feerate * 1e5')
    laterblk=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq '.feerate * 1e5')
fi

firstblk="$(math_round_up $firstblk) sat/vB"
secondblk="$(math_round_up $secondblk) sat/vB"
thirdblk="$(math_round_up $thirdblk) sat/vB"
laterblk="$(math_round_up $laterblk) sat/vB"

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
