#!/usr/bin/env bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tcols=$(tput cols)
time_now=$(date +%s)
re_price='^[0-9]+([.][0-9]+)?$'

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

if [[ -f "$SCRIPT_DIR/aths.json" ]]; then
    time_file=$(stat -c %Y "$SCRIPT_DIR/aths.json")
    time_current=$(date +%s)
    if ((time_file + 300 < time_current)) ||
        ! jq -e . "$SCRIPT_DIR/aths.json" >/dev/null 2>&1; then
        rm -f "$SCRIPT_DIR/aths.json"
    else
        ath_prices=$(cat "$SCRIPT_DIR/aths.json")
    fi
fi

# Gets the price according to the symbol parameter and defined time.
get_price() {
    time_gap=$([ -n "$2" ] && date -d "$2 ago" +%s || echo $time_now)
    lower_bound=$((time_gap - 20))
    upper_bound=$((time_gap + 20))
    value=$(echo $prices | jq --argjson lower "$lower_bound" --argjson upper "$upper_bound" \
            '[.[] | select(.timestamp >= $lower and .timestamp <= $upper)]')
    [[ "$value" != "[]" ]] && echo $value | jq -r ".[0].$1"
}

# Updates the list of prices obtained from one of the exchange APIs.
update_price() {
    json_data='[{"timestamp":'$time_now
    for currency in $(echo $exchanges | jq -r ".$1.api | keys[]"); do
        jq_price=$(echo $exchanges | jq -r ".$1.jq_price")
        api_url=$(echo $exchanges | jq -r ".$1.api.$currency")
        json=$(curl -s $api_url)
        price=$(echo $json | jq -r "$jq_price?")
        if ! [[ "$price" =~ $re_price ]]; then
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
    if [ -n "$3" ]; then
        if (( $(echo "$1 > $3" | bc -l) )); then
            color="\033[1;33m"
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
        if [[ "$price_ago" =~ $re_price ]]; then
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
        line_title="(Wait a few minutes)"
    fi
    text="$(printf '%*s' $(( ( $tcols - ${#line_title} ) / 2 )) '')\033[37m${line_title}\033[0m\n"
    if [[ "${#line_per}" -gt 0 ]]; then
        text+="$(printf '%*s' $(( ( $tcols - ${#line_title} ) / 2 )) '')\033[37m${line_per}\033[0m"
    fi
    echo "$text"
}

# Checks price variations and sounds the alarm according to conditions.
check_alarm() {
    re='^[<>]=?\ -?[0-9]+(\.[0-9]+)?$'
    while read alarm; do
        condition=$(echo $alarm | jq -r ".condition")
        read time_ago variation <<< $(echo $condition | awk '{print $1, $2 " " $3}')
        if ! date -d "$time_ago ago" >/dev/null 2>&1 ||
            ! [[ "$variation" =~ $re ]]; then
            echo "Alarm condition '$condition' is invalid."
            exit 1
        fi

        sound=$(echo $alarm | jq -r ".sound")
        if ! [[ -f "$SCRIPT_DIR/alarms/$sound" ]]; then
            echo -e "Sound file not found:\n-PATH=$SCRIPT_DIR/alarms/$sound"
            exit 1
        fi

        interval=$(echo $alarm | jq -r ".interval")
        last=$(echo $last_alarm | jq -r --arg i "$interval" '.[$i]')
        if (( $time_now - $last < $interval )); then
            continue
        fi

        currency=$(echo $alarm | jq -r ".currency")
        if [[ -z "$currency" ]];then
            $currency=$curdef
        fi

        price_now=$(get_price $currency)
        price_ago=$(get_price $currency $time_ago)
        if ! [[ "$price_ago" =~ $re_price ]] ||
            ! (( $(echo "$price_now / $price_ago - 1 $variation" | bc -l) )); then
            continue
        fi

        nohup play -q "$SCRIPT_DIR/alarms/$sound" >/dev/null 2>&1 &
        last_alarm=$(echo $last_alarm | jq --arg i "$interval" --argjson t "$time_now" '.[$i] = $t')
        echo $last_alarm | jq -c . > "$SCRIPT_DIR/last_alarm.json"
        break
    done < <(echo $alarms | jq -c ".[]")
}

# Calculates columns for ASCII art based on font and number.
calc_figlet_cols() {
    local font="$1" price="$2"
    local fncols char_length only_numbers

    case "$font" in
        big) fncols=6.9 ;;
        small) fncols=6.2 ;;
        *) fncols=4 ;;
    esac

    only_numbers=$(echo "$price" | tr -cd '0-9')
    char_length="${#only_numbers}"
    echo $(awk "BEGIN {print int($char_length * $fncols + 2)}")
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
    cat << EOF
Currency values ​​were not found in exchange APIs.
Possible causes:
- APIs are not working
- Your network is offline with the internet
EOF
    exit 1
fi
curdef=$(echo $exchanges | jq -r ".${exchange_selected}.api | to_entries | first(.[]).key")

if [ -z "$ath_prices" ]; then
    json=$(curl -s "https://api.coingecko.com/api/v3/coins/bitcoin")
    ath_prices="{"
    for currency in $(echo $exchanges | jq -r ".${exchange_selected}.api | keys[]"); do
        price=$(echo $json | jq -r ".market_data.ath.$currency?")
        if [[ "$price" =~ $re_price ]]; then
            price=$(LC_NUMERIC=C printf "%.2f" $price)
        else
            price=""
        fi
        ath_prices+="\"${currency}\":\"${price}\","
    done
    ath_prices="${ath_prices:0:-1}}"

    if ! jq -e . >/dev/null 2>&1 <<< "$ath_prices"; then
        echo "Failed to parse JSON, or got false/null."
        exit 1
    fi
fi

body="$(printf '%*s' $(( ( $tcols - 16 - ${#exchange_selected} ) / 2 )) '')"
body+="Bitcoin Price - ${exchange_selected^}\n\n"

# Sets the color of the current dollar price compared to the price 30 seconds ago
price_now=$(get_price $curdef)
price_ago=$(get_price $curdef 30sec)
price_ath=$(echo $ath_prices | jq -r ".${curdef}")
color=$(variation_color $price_now $price_ago $price_ath)

# Current dollar price with capital letters
price_formatted=$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')

fonts=("big" "small" "mini")
font=0
while [ $font -lt 2 ]; do
    fgt_cols=$(calc_figlet_cols "${fonts[$font]}" "$price_formatted")
    (( fgt_cols < tcols )) && break
    font=$((font + 1))
done

[ $font -eq 2 ] && body+="\n"
body+="\033[1;${color:5}$(figlet -f ${fonts[$font]} -w $tcols -c -m1 "$price_formatted")\033[0m\n"
[ $font -ge 1 ] && body+="\n\n"

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
    price_ath=$(echo $ath_prices | jq -r ".${currency}")
    color=$(variation_color $price_now $price_ago $price_ath)

    # Current price with small letters
    price_formatted="${currency^^} "$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')
    length=$(( length + ${#price_formatted} ))
    small_prices+="${color}${price_formatted}"
done
small_prices+="\033[0m · "

body+=$(echo -n "$(printf '%*s' $(( ($tcols - $length) / 2 )) '')")"$small_prices"
if [ $font -ge 1 ]; then body+="\n"; fi

ls_title=("5m" "15m" "1h" "2h" "4h" "8h" "12h" "1d")
ls_ago=("5min" "15min" "1hour" "2hour" "4hour" "8hour" "12hour" "1day")
body+="\n\n$(ls_vartime $ls_title $ls_ago)"

ath_news=$ath_prices
for currency in $(echo $exchanges | jq -r ".${exchange_selected}.api | keys[]"); do
    price_now=$(get_price $currency)
    price_ath=$(echo $ath_prices | jq -r ".${currency}")
    if [ -z "$price_ath" ] ||
        (( $(echo "$price_now <= $price_ath" | bc -l) )); then
        continue
    fi
    ath_news=$(echo $ath_news | jq --arg c "$currency" --arg p "$price_now" '.[$c] = $p')
done
echo $ath_news | jq -c . > "$SCRIPT_DIR/aths.json"

if [ "$ath_prices" != "$ath_news" ]; then
    nohup play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" >/dev/null 2>&1 &
elif [[ -n "$alarms" ]]; then
    check_alarm
fi
echo -ne "$body"
