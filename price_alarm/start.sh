#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

prices="[]"
price_usd=0
price_brl=0

if [[ ! -f "$SCRIPT_DIR/prices.json" ]]; then
    touch "$SCRIPT_DIR/prices.json"
elif jq empty "$SCRIPT_DIR/prices.json" >/dev/null 2>&1; then
    prices=$(cat "$SCRIPT_DIR/prices.json")
fi
time_now=$(date +%s)

get_price() {
    time_gap=$([ -n "$2" ] && date -d "$2 ago" +%s || echo $time_now)
    lower_bound=$((time_gap - 20))
    upper_bound=$((time_gap + 20))
    value=$(echo $prices | jq --argjson lower "$lower_bound" --argjson upper "$upper_bound" \
            '[.[] | select(.timestamp >= $lower and .timestamp <= $upper)]')
    [[ "$value" != "[]" ]] && echo $value | jq ".[0].$1" | sed 's/"//g' || echo ""
}

update_price() {
    json_btcbrl=$(curl -s https://api.coinbase.com/v2/prices/BTC-BRL/spot)
    json_btcusd=$(curl -s https://api.coinbase.com/v2/prices/BTC-USD/spot)
    if [[ $json_btcbrl =~ "Not Found" || $json_btcusd =~ "Not Found" ]]; then
        exit 1
    fi

    price_usd=$(echo $json_btcusd | jq .data.amount | sed 's/"//g' | xargs -I {} printf "%.2f" {} | sed 's/,/./g')
    price_brl=$(echo $json_btcbrl | jq .data.amount | sed 's/"//g' | xargs -I {} printf "%.2f" {} | sed 's/,/./g')
    json_data="[{\"timestamp\":$(date +%s),\"usd\":$price_usd,\"brl\":$price_brl}]"
    prices=$(echo $prices | jq ". += $json_data")

    # Filters the JSON and keeps only records with timestamps from the last 24 hours
    old_time=$(date -d "1 day ago 1 minute ago" +%s)
    prices=$(echo $prices | jq --argjson cutoff "$old_time" '[.[] | select(.timestamp >= $cutoff)]')
    echo $prices | jq -c . > "$SCRIPT_DIR/prices.json"
}

# Sets the color of the current price compared to the previous price
variation_color() {
    color="\033[37m"
    if [[ -n "$2" ]]; then
        if (( $(echo "$1 > $2" | bc -l) )); then
            color="\033[32m"
        elif (( $(echo "$1 < $2" | bc -l) )); then
            color="\033[31m"
        fi
    fi
    echo $color
}

# Lists the price variation over several times.
ls_vartime() {
    ls_title=$1
    ls_ago=$2
    line_title=""
    line_per=""
    for index in "${!ls_title[@]}"; do
        price_ago="$(get_price usd ${ls_ago[$index]})" 
        if [[ -n "$price_ago" ]]; then
            title="$(printf '%*s' $(( (8 - ${#ls_title[$index]}) / 2 )) '')${ls_title[$index]}"
            title+="$(printf '%*s' $(( 8 - ${#title} )) '')"
            per_num=$(echo "scale=4; (($price_usd / $price_ago - 1) * 100)" | bc)
            color=$(variation_color $per_num 0)
            per_num=$(echo $per_num | xargs -I {} printf "%+.2f" {})"%"
            line_title+="$title"
            per_num="$(printf '%*s' $(( (8 - ${#per_num}) / 2 )) '')$per_num"
            per_num+="$(printf '%*s' $(( 8 - ${#per_num} )) '')"
            line_per+="${color}$per_num"
        fi
    done

    if [[ -z "$line_title" ]]; then
        line_title="Loading..."
    fi
    text="$(printf '%*s' $(( ( 64 - ${#line_title} ) / 2 )) '')\033[37m${line_title}\033[0m\n"
    if [[ "${#line_per}" -gt 0 ]]; then
        text+="$(printf '%*s' $(( ( 64 - ${#line_title} ) / 2 )) '')\033[37m${line_per}\033[0m"
    fi
    echo "$text"
}

last_alarm=(0 0 0 0 0 0)
check_alarm() {
    price_ago=( $(get_price usd 5min) $(get_price usd 15min) $(get_price usd 30min)
                $(get_price usd 1hour) $(get_price usd 2hour) $(get_price usd 4hour)
                $(get_price usd 8hour) $(get_price usd 12hour) $(get_price usd 1day) )

    if (( $time_now - ${last_alarm[0]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[8]} - 1 > 0.13" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[7]} - 1 > 0.086" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[6]} - 1 > 0.07" | bc -l) )))
        }; then
        last_alarm[0]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" &
    elif (( $time_now - ${last_alarm[0]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[8]} - 1 < -0.13" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[7]} - 1 < -0.086" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[6]} - 1 < -0.07" | bc -l) )))
        }; then
        last_alarm[0]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-long.mp3" &
    elif (( $time_now - ${last_alarm[1]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[8]} - 1 > 0.065" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[7]} - 1 > 0.043" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[6]} - 1 > 0.035" | bc -l) )))
        }; then
        last_alarm[1]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-long.mp3" &
    elif (( $time_now - ${last_alarm[1]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[8]} - 1 < -0.065" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[7]} - 1 < -0.043" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[6]} - 1 < -0.035" | bc -l) )))
        }; then
        last_alarm[1]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-long.wav" &
    elif (( $time_now - ${last_alarm[2]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[5]} - 1 > 0.05" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[4]} - 1 > 0.04" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[3]} - 1 > 0.03" | bc -l) )))
        }; then
        last_alarm[2]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" &
    elif (( $time_now - ${last_alarm[2]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[5]} - 1 < -0.05" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[4]} - 1 < -0.04" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[3]} - 1 < -0.03" | bc -l) )))
        }; then
        last_alarm[2]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-long.mp3" &
    elif (( $time_now - ${last_alarm[3]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[5]} - 1 > 0.03" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[4]} - 1 > 0.025" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[3]} - 1 > 0.02" | bc -l) )))
        }; then
        last_alarm[3]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-long.mp3" &
    elif (( $time_now - ${last_alarm[3]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[5]} - 1 < -0.03" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[4]} - 1 < -0.025" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[3]} - 1 < -0.02" | bc -l) )))
        }; then
        last_alarm[3]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-long.wav" &
    elif (( $time_now - ${last_alarm[4]} >= 600 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[2]} - 1 > 0.036" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[1]} - 1 > 0.024" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[0]} - 1 > 0.012" | bc -l) )))
        }; then
        last_alarm[4]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-short.mp3" &
    elif (( $time_now - ${last_alarm[4]} >= 600 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[2]} - 1 < -0.036" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[1]} - 1 < -0.024" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[0]} - 1 < -0.012" | bc -l) )))
        }; then
        last_alarm[4]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-short.mp3" &
    elif (( $time_now - ${last_alarm[5]} >= 900 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[2]} - 1 > 0.018" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[1]} - 1 > 0.012" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[0]} - 1 > 0.006" | bc -l) )))
        }; then
        last_alarm[5]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-short.mp3" &
    elif (( $time_now - ${last_alarm[5]} >= 900 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[2]} - 1 < -0.018" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[1]} - 1 < -0.012" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_usd / ${price_ago[0]} - 1 < -0.006" | bc -l) )))
        }; then
        last_alarm[5]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-short.mp3" &
    fi
}

while true; do
    update_price

    body="\n$(printf '%*s' $(( ( 64 - 23 ) / 2 )) '')"
    body+="Bitcoin Price - Coinbase\n\n"

    # Sets the color of the current dollar price compared to the price 30 seconds ago
    price_ago=$(get_price usd 30sec)
    color=$(variation_color $price_usd $price_ago)

    # Current dollar price with capital letters
    body+="\033[1;${color:5}$(figlet -f big -w 64 -c -m-0 "$ $(echo -n "$price_usd" | \
        sed 's/\./,/g' | sed ':a;s/\B[0-9]\{3\}\>/.\0/;ta')")\033[0m\n"

    # Current dollar price with small print
    body+="$color"$(echo -n "$(printf '%*s' $(( (64 - 32) / 2 )) '')USD $price_usd" | \
        sed 's/\./,/g' | sed ':a;s/\B[0-9]\{3\}\>/.\0/;ta')

    body+="\033[0m  ·  "

    # Sets the color of the current real price compared to the price 30 seconds ago
    price_ago=$(get_price brl 30sec)
    color=$(variation_color $price_usd $price_ago)

    # Current Brazilian real price with small print
    body+="$color"$(echo -n "BRL $price_brl" | sed 's/\./,/g' | sed ':a;s/\B[0-9]\{3\}\>/.\0/;ta')

    ls_title=("5m" "15m" "1h" "2h" "4h" "8h" "12h" "1d")
    ls_ago=("5min" "15min" "1hour" "2hour" "4hour" "8hour" "12hour" "1day")
    body+="\n\n$(ls_vartime $ls_title $ls_ago)"

    echo -ne "$body"
    check_alarm
    sleep 30s
done
