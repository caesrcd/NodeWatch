#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

if ! [[ -f "$SCRIPT_DIR/exchanges.json" ]]; then
    echo "File 'exchanges.json' not found."
    exit 1
elif ! jq -e . "$SCRIPT_DIR/exchanges.json" >/dev/null 2>&1; then
    echo "Failed to parse JSON in file 'exchanges.json'."
    exit 1
fi
exchanges=$(cat "$SCRIPT_DIR/exchanges.json")

prices="[]"
if [[ -f "$SCRIPT_DIR/prices.json" ]]; then
    if jq -e . "$SCRIPT_DIR/prices.json" >/dev/null 2>&1; then
        prices=$(cat "$SCRIPT_DIR/prices.json")
    fi
fi
time_now=$(date +%s)

get_price() {
    time_gap=$([ -n "$2" ] && date -d "$2 ago" +%s || echo $time_now)
    lower_bound=$((time_gap - 20))
    upper_bound=$((time_gap + 20))
    value=$(echo $prices | jq --argjson lower "$lower_bound" --argjson upper "$upper_bound" \
            '[.[] | select(.timestamp >= $lower and .timestamp <= $upper)]')
    [[ "$value" != "[]" ]] && echo $value | jq -r ".[0].$1" || echo ""
}

update_price() {
    re='^[0-9]+([.][0-9]+)?$'
    json_data="[{\"timestamp\":$(date +%s)"
    for currency in $(echo $exchanges | jq -r ".${1}.api | keys[]"); do
        jq_price=$(echo $exchanges | jq -r ".${1}.jq_price")
        api_url=$(echo $exchanges | jq -r ".${1}.api.${currency}")
        json=$(curl -s $api_url)
        price=$(echo $json | jq -r "$jq_price")
        if [[ "$price" == "null" ]]; then
            return 1
        elif ! [[ $price =~ $re ]]; then
            echo "Price isn't a number: $price"
            return 1
        fi
        price=$(LC_NUMERIC=C printf "%.2f" $price)
        json_data+=",\"${currency}\":${price}"
    done
    json_data+="}]"

    prices=$(echo $prices | jq ". += $json_data")

    # Filters the JSON and keeps only records with timestamps from the last 24 hours
    old_time=$(date -d "1 day ago 1 minute ago" +%s)
    prices=$(echo $prices | jq --argjson cutoff "$old_time" '[.[] | select(.timestamp >= $cutoff)]')

    if ! jq -e . >/dev/null 2>&1 <<< "$prices"; then
        echo "Failed to parse JSON, or got false/null."
        exit 1
    fi

    echo $prices | jq -c . > "$SCRIPT_DIR/prices.json"
    return 0
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
    price_now=$(get_price usd 0sec)
    for index in "${!ls_title[@]}"; do
        price_ago="$(get_price usd ${ls_ago[$index]})"
        if [[ -n "$price_ago" ]]; then
            title="$(printf '%*s' $(( (8 - ${#ls_title[$index]}) / 2 )) '')${ls_title[$index]}"
            title+="$(printf '%*s' $(( 8 - ${#title} )) '')"
            per_num=$(echo "scale=4; (($price_now / $price_ago - 1) * 100)" | bc)
            color=$(variation_color $per_num 0)
            per_num=$(awk "BEGIN {printf \"%+.2f\", $per_num}")"%"
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
    price_now=$(get_price usd 0sec)
    price_ago=( $(get_price usd 5min) $(get_price usd 15min) $(get_price usd 30min)
                $(get_price usd 1hour) $(get_price usd 2hour) $(get_price usd 4hour)
                $(get_price usd 8hour) $(get_price usd 12hour) $(get_price usd 1day) )

    if (( $time_now - ${last_alarm[0]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_now / ${price_ago[8]} - 1 > 0.13" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_now / ${price_ago[7]} - 1 > 0.086" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_now / ${price_ago[6]} - 1 > 0.07" | bc -l) )))
        }; then
        last_alarm[0]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" &
    elif (( $time_now - ${last_alarm[0]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_now / ${price_ago[8]} - 1 < -0.13" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_now / ${price_ago[7]} - 1 < -0.086" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_now / ${price_ago[6]} - 1 < -0.07" | bc -l) )))
        }; then
        last_alarm[0]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-long.mp3" &
    elif (( $time_now - ${last_alarm[1]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_now / ${price_ago[8]} - 1 > 0.065" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_now / ${price_ago[7]} - 1 > 0.043" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_now / ${price_ago[6]} - 1 > 0.035" | bc -l) )))
        }; then
        last_alarm[1]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-long.mp3" &
    elif (( $time_now - ${last_alarm[1]} >= 36000 )) && {
            ([[ -n "${price_ago[8]}" ]] &&
                (( $(echo "$price_now / ${price_ago[8]} - 1 < -0.065" | bc -l) ))) ||
            ([[ -n "${price_ago[7]}" ]] &&
                (( $(echo "$price_now / ${price_ago[7]} - 1 < -0.043" | bc -l) ))) ||
            ([[ -n "${price_ago[6]}" ]] &&
                (( $(echo "$price_now / ${price_ago[6]} - 1 < -0.035" | bc -l) )))
        }; then
        last_alarm[1]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-long.wav" &
    elif (( $time_now - ${last_alarm[2]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_now / ${price_ago[5]} - 1 > 0.05" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_now / ${price_ago[4]} - 1 > 0.04" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_now / ${price_ago[3]} - 1 > 0.03" | bc -l) )))
        }; then
        last_alarm[2]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" &
    elif (( $time_now - ${last_alarm[2]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_now / ${price_ago[5]} - 1 < -0.05" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_now / ${price_ago[4]} - 1 < -0.04" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_now / ${price_ago[3]} - 1 < -0.03" | bc -l) )))
        }; then
        last_alarm[2]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-long.mp3" &
    elif (( $time_now - ${last_alarm[3]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_now / ${price_ago[5]} - 1 > 0.03" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_now / ${price_ago[4]} - 1 > 0.025" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_now / ${price_ago[3]} - 1 > 0.02" | bc -l) )))
        }; then
        last_alarm[3]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-long.mp3" &
    elif (( $time_now - ${last_alarm[3]} >= 7200 )) && {
            ([[ -n "${price_ago[5]}" ]] &&
                (( $(echo "$price_now / ${price_ago[5]} - 1 < -0.03" | bc -l) ))) ||
            ([[ -n "${price_ago[4]}" ]] &&
                (( $(echo "$price_now / ${price_ago[4]} - 1 < -0.025" | bc -l) ))) ||
            ([[ -n "${price_ago[3]}" ]] &&
                (( $(echo "$price_now / ${price_ago[3]} - 1 < -0.02" | bc -l) )))
        }; then
        last_alarm[3]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-long.wav" &
    elif (( $time_now - ${last_alarm[4]} >= 600 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_now / ${price_ago[2]} - 1 > 0.036" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_now / ${price_ago[1]} - 1 > 0.024" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_now / ${price_ago[0]} - 1 > 0.012" | bc -l) )))
        }; then
        last_alarm[4]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-high-short.mp3" &
    elif (( $time_now - ${last_alarm[4]} >= 600 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_now / ${price_ago[2]} - 1 < -0.036" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_now / ${price_ago[1]} - 1 < -0.024" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_now / ${price_ago[0]} - 1 < -0.012" | bc -l) )))
        }; then
        last_alarm[4]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-high-short.mp3" &
    elif (( $time_now - ${last_alarm[5]} >= 900 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_now / ${price_ago[2]} - 1 > 0.018" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_now / ${price_ago[1]} - 1 > 0.012" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_now / ${price_ago[0]} - 1 > 0.006" | bc -l) )))
        }; then
        last_alarm[5]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/win-small-short.mp3" &
    elif (( $time_now - ${last_alarm[5]} >= 900 )) && {
            ([[ -n "${price_ago[2]}" ]] &&
                (( $(echo "$price_now / ${price_ago[2]} - 1 < -0.018" | bc -l) ))) ||
            ([[ -n "${price_ago[1]}" ]] &&
                (( $(echo "$price_now / ${price_ago[1]} - 1 < -0.012" | bc -l) ))) ||
            ([[ -n "${price_ago[0]}" ]] &&
                (( $(echo "$price_now / ${price_ago[0]} - 1 < -0.006" | bc -l) )))
        }; then
        last_alarm[5]=$(date +%s)
        play -q "$SCRIPT_DIR/alarms/loss-small-short.mp3" &
    fi
}

exchange_selected=""
for exchange in $(echo $exchanges | jq -r "keys[]"); do
    update_price "$exchange"
    if [ "$?" -eq 0 ]; then
        exchange_selected="$exchange"
        break
    fi
done
if [[ -z "$exchange_selected" ]]; then
    echo "Exchange APIs are currently not working."
    exit 1
fi

body="$(printf '%*s' $(( ( 64 - 13 ) / 2 )) '')"
body+="Bitcoin Price\n\n"

# Sets the color of the current dollar price compared to the price 30 seconds ago
price_now=$(get_price usd 0sec)
price_ago=$(get_price usd 30sec)
color=$(variation_color $price_now $price_ago)

price_formatted=$(awk "BEGIN {printf \"%'\047.2f\", $price_now}")

# Current dollar price with capital letters
body+="\033[1;${color:5}$(figlet -f big -w 64 -c -m-0 "$ $price_formatted")\033[0m\n"

# Current others price with small letters
length=4
length=$(( length + ${#price_formatted} ))
small_prices="$color"$(echo -n "USD $price_formatted")
for currency in $(echo $exchanges | jq -r ".${exchange_selected}.api | keys[]"); do
    if [[ "$currency" == "usd" ]]; then
        continue
    fi
    small_prices+="\033[0m · "
    length=$(( length + 3 ))

    # Sets the color of the current price compared to the price 30 seconds ago
    price_now=$(get_price ${currency} 0sec)
    price_ago=$(get_price ${currency} 30sec)
    color=$(variation_color $price_now $price_ago)

    # Current price with small letters
    price_formatted="${currency^^} "$(awk "BEGIN {printf \"%'\047.2f\", $price_now}")
    length=$(( length + ${#price_formatted} ))
    small_prices+="${color}${price_formatted}"
done
body+=$(echo -n "$(printf '%*s' $(( (64 - $length) / 2 )) '')")"$small_prices"

ls_title=("5m" "15m" "1h" "2h" "4h" "8h" "12h" "1d")
ls_ago=("5min" "15min" "1hour" "2hour" "4hour" "8hour" "12hour" "1day")
body+="\n\n$(ls_vartime $ls_title $ls_ago)"

echo -ne "$body"
check_alarm
