#!/usr/bin/env sh

forecast_type=$1

# Round numbers up to the nearest integer except when it is less than 1
math_round_up() {
    _mru_number="$1"
    if echo "$_mru_number" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
        _mru_number=$(awk -v num="$_mru_number" 'BEGIN {
            if (num > 0.999) print int(num) + (num > int(num));
            else if (num < 0.01) print (num < 0.01 ? num : sprintf("%.3f", num));
            else if (num < 0.1) print sprintf("%.2f", num);
            else if (num < 1) print sprintf("%.1f", num);
            else print num;
        }')
    fi
    echo "$_mru_number"
}

# Find the maximum between two or more elements passed to it as arguments.
math_max() {
    _mhmx_max="$1"
    for num in "$@"; do
        _mhmx_max=$(printf '%s\n%s' "$_mhmx_max" "$num" | awk -v max="$_mhmx_max" '{if ($1 >= max) max=$1} END {print max}')
    done
    echo "$_mhmx_max"
}

# Find the minimum between two or more elements passed to it as arguments.
math_min() {
    _mhmn_min="$1"
    for num in "$@"; do
        _mhmn_min=$(printf '%s\n%s' "$_mhmn_min" "$num" | awk -v min="$_mhmn_min" '{if ($1 <= min) min=$1} END {print min}')
    done
    echo "$_mhmn_min"
}

output=$(bitcoin-cli -rpcwait estimatesmartfee 1 2>&1)
if echo "$output" | jq -e 'has("errors")' >/dev/null 2>&1; then
    forecast_type="mempool"
elif echo "$output" | grep -q "Fee estimation disabled"; then
    forecast_type="mempool"
fi
mempoolinfo=$(bitcoin-cli -rpcwait getmempoolinfo)
mempool_loaded=$(echo "$mempoolinfo" | jq -r '.loaded')
if [ "$mempool_loaded" = "true" ] && [ "$forecast_type" = "median" ]; then
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
    for i in 0 1 2; do
        nblk=$((i + 1))
        medianfee=$(echo "$fees" | jq -r ".[${i}] // 0")
        if awk -v x="$medianfee" 'BEGIN {exit !(x != 0)}'; then
            [ -n "$prev_fee" ] && medianfee=$(echo "$prev_fee $medianfee" | awk '{print ($1 + $2) / 2}')
            prev_fee=$(eval echo "\$block$nblk")
        fi
        maxfee=$(math_max "$minimum_fee" "$medianfee")
        eval "block$nblk=\"$maxfee\""
    done

    minfee2x=$(awk -v fee="$minimum_fee" 'BEGIN {print fee * 2}')
    economyfee=$(math_min "$minfee2x" "$block3")
    laterblk=$(math_max "$minimum_fee" "$economyfee")

    block1=$(math_max "$block1" "$block2" "$block3" "$laterblk")
    block2=$(math_max "$block2" "$block3" "$laterblk")
    block3=$(math_max "$block3" "$laterblk")
elif [ "$forecast_type" = "mempool" ]; then
    fees_recommended=$(curl -s "https://mempool.space/api/v1/fees/recommended")
    if [ -z "$fees_recommended" ]; then
        echo "Error: Failed to retrieve data from the API."
        exit 1
    fi
    block1=$(echo "$fees_recommended" | jq -r '.fastestFee')
    block2=$(echo "$fees_recommended" | jq -r '.halfHourFee')
    block3=$(echo "$fees_recommended" | jq -r '.hourFee')
    laterblk=$(echo "$fees_recommended" | jq -r '.economyFee')
else
    block1=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq '.feerate * 1e5')
    block2=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq '.feerate * 1e5')
    block3=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq '.feerate * 1e5')
    laterblk=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq '.feerate * 1e5')
fi

block1=$(math_round_up "$block1")" sat/vB"
block2=$(math_round_up "$block2")" sat/vB"
block3=$(math_round_up "$block3")" sat/vB"
laterblk=$(math_round_up "$laterblk")" sat/vB"

tcols=$(tput cols)

printf "%*sTransaction Fees\n\n" $(( (tcols - 15) / 2 )) ""
printf "%*s\033[0mBlock 1\n" $(( (tcols - 7) / 2 )) ""
printf "%*s\033[35m%s\n\n" $(( (tcols - ${#block1}) / 2 )) "" "$block1"
printf "%*s\033[0mBlock 2\n" $(( (tcols - 7) / 2 )) ""
printf "%*s\033[35m%s\n\n" $(( (tcols - ${#block2}) / 2 )) "" "$block2"
printf "%*s\033[0mBlock 3\n" $(( (tcols - 7) / 2 )) ""
printf "%*s\033[35m%s\n\n" $(( (tcols - ${#block3}) / 2 )) "" "$block3"
printf "%*s\033[0mLater block\n" $(( (tcols - 11) / 2 )) ""
printf "%*s\033[35m%s\n\n" $(( (tcols - ${#laterblk}) / 2 )) "" "$laterblk"
