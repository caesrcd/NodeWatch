#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
tcols=$(tput cols)

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

last_alarm="{}"
if [[ -f "$SCRIPT_DIR/last_alarm.json" ]]; then
    if jq -e . "$SCRIPT_DIR/last_alarm.json" >/dev/null 2>&1; then
        last_alarm=$(cat "$SCRIPT_DIR/last_alarm.json")
    fi
fi

if [[ -f "$SCRIPT_DIR/alarms.json" ]]; then
    if ! jq -e . "$SCRIPT_DIR/alarms.json" >/dev/null 2>&1; then
        echo "Failed to parse JSON in file 'alarms.json'."
        exit 1
    fi
    alarms=$(cat "$SCRIPT_DIR/alarms.json")
fi

time_now=$(date +%s)

# Gets the price according to the symbol parameter and defined time.
get_price() {
    time_gap=$([ -n "$2" ] && date -d "$2 ago" +%s || echo $time_now)
    lower_bound=$((time_gap - 20))
    upper_bound=$((time_gap + 20))
    value=$(echo $prices | jq --argjson lower "$lower_bound" --argjson upper "$upper_bound" \
            '[.[] | select(.timestamp >= $lower and .timestamp <= $upper)]')
    [[ "$value" != "[]" ]] && echo $value | jq -r ".[0].$1" || echo ""
}

# Updates the list of prices obtained from one of the exchange APIs.
update_price() {
    re='^[0-9]+([.][0-9]+)?$'
    json_data='[{"timestamp":'$time_now
    for currency in $(echo $exchanges | jq -r ".$1.api | keys[]"); do
        jq_price=$(echo $exchanges | jq -r ".$1.jq_price")
        api_url=$(echo $exchanges | jq -r ".$1.api.$currency")
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
    old_time=$(date -d "1day ago 1min ago" +%s)
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
    price_now=$(get_price $curdef)
    for index in "${!ls_title[@]}"; do
        price_ago="$(get_price $curdef ${ls_ago[$index]})"
        if [[ -n "$price_ago" ]]; then
            title="$(printf '%*s' $(( (8 - ${#ls_title[$index]}) / 2 )) '')${ls_title[$index]}"
            title+="$(printf '%*s' $(( 8 - ${#title} )) '')"
            if (( ${#line_title} + ${#title} > $tcols )); then
                break;
            fi
            per_num=$(echo "scale=4; (($price_now / $price_ago - 1) * 100)" | bc)
            color=$(variation_color $per_num 0)
            per_num=$(awk -v per="$per_num" 'BEGIN {printf "%+.2f", per}')"%"
            line_title+="$title"
            per_num="$(printf '%*s' $(( (8 - ${#per_num}) / 2 )) '')$per_num"
            per_num+="$(printf '%*s' $(( 8 - ${#per_num} )) '')"
            line_per+="${color}$per_num"
        fi
    done

    if [[ -z "$line_title" ]]; then
        line_title="Loading..."
    fi
    text="$(printf '%*s' $(( ( $tcols - ${#line_title} ) / 2 )) '')\033[37m${line_title}\033[0m\n"
    if [[ "${#line_per}" -gt 0 ]]; then
        text+="$(printf '%*s' $(( ( $tcols - ${#line_title} ) / 2 )) '')\033[37m${line_per}\033[0m"
    fi
    echo "$text"
}

# Checks price variations and sounds the alarm according to conditions.
check_alarm() {
    price_now=$(get_price $curdef)
    while read alarm; do
        condition=$(echo $alarm | jq -r ".condition")
        read time_ago variation <<< $(echo $condition | awk '{print $1, $2 " " $3}')
        if ! date -d "$time_ago ago" >/dev/null 2>&1; then
            echo "Alarm condition '$condition' is invalid."
            exit 1
        fi

        interval=$(echo $alarm | jq -r ".interval")
        last=$(echo $last_alarm | jq -r --arg i "$interval" '.[$i]')
        if (( $time_now - $last < $interval )); then
            continue
        fi

        price_ago=$(get_price $curdef $time_ago)
        if [[ -z "$price_ago" ]] ||
            ! (( $(echo "$price_now / $price_ago - 1 $variation" | bc -l) )); then
            continue
        fi

        sound=$(echo $alarm | jq -r ".sound")
        play -q "$SCRIPT_DIR/alarms/$sound"
        last_alarm=$(echo $last_alarm | jq --arg i "$interval" --argjson t "$time_now" '.[$i] = $t')
        echo $last_alarm | jq -c . > "$SCRIPT_DIR/last_alarm.json"
        break
    done < <(echo $alarms | jq -c ".[]")
}

exchange_selected=""
for exchange in $(echo $exchanges | jq -r "to_entries[] | .key"); do
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
curdef=$(echo $exchanges | jq -r ".${exchange_selected}.api | to_entries | first(.[]).key")

body="$(printf '%*s' $(( ( $tcols - 13 ) / 2 )) '')"
body+="Bitcoin Price\n\n"

# Sets the color of the current dollar price compared to the price 30 seconds ago
price_now=$(get_price $curdef)
price_ago=$(get_price $curdef 30sec)
color=$(variation_color $price_now $price_ago)

price_formatted=$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')

# Current dollar price with capital letters
if [[ $tcols -gt 60 ]]; then font="big"
elif [[ $tcols -gt 50 ]]; then font="small"
elif [[ $tcols -gt 40 ]]; then font="script"
else font="mini"
fi

body+="\033[1;${color:5}$(figlet -f $font -w $tcols -c -m-0 "$price_formatted")\033[0m\n"

# Current others price with small letters
length=3
for currency in $(echo $exchanges | jq -r ".${exchange_selected}.api | to_entries[] | .key"); do
    if [[ "$currency" == "$curdef" ]]; then
        continue
    fi
    small_prices+="\033[0m · "
    length=$(( length + 3 ))

    # Sets the color of the current price compared to the price 30 seconds ago
    price_now=$(get_price ${currency})
    price_ago=$(get_price ${currency} 30sec)
    color=$(variation_color $price_now $price_ago)

    # Current price with small letters
    price_formatted="${currency^^} "$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')
    length=$(( length + ${#price_formatted} ))
    small_prices+="${color}${price_formatted}"
done
small_prices+="\033[0m · "

body+=$(echo -n "$(printf '%*s' $(( ($tcols - $length) / 2 )) '')")"$small_prices"

ls_title=("5m" "15m" "1h" "2h" "4h" "8h" "12h" "1d")
ls_ago=("5min" "15min" "1hour" "2hour" "4hour" "8hour" "12hour" "1day")
body+="\n\n$(ls_vartime $ls_title $ls_ago)"

echo -ne "$body"
if [[ -n "$alarms" ]]; then
    check_alarm
fi
