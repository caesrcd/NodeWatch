#!/usr/bin/env sh

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

tcols=$(tput cols)
time_now=$(date +%s)
re_price='^[0-9]+([.][0-9]+)?$'

if ! [ -f "$SCRIPT_DIR/exchanges.json" ]; then
    echo "File 'exchanges.json' not found."
    exit 1
elif ! jq -e . "$SCRIPT_DIR/exchanges.json" >/dev/null 2>&1; then
    echo "Failed to parse JSON in file 'exchanges.json'."
    exit 1
fi
exchanges=$(cat "$SCRIPT_DIR/exchanges.json")

prices="[]"
if [ -f "$SCRIPT_DIR/prices.json" ]; then
    if jq -e . "$SCRIPT_DIR/prices.json" >/dev/null 2>&1; then
        prices=$(cat "$SCRIPT_DIR/prices.json")
    fi
fi

last_alarm="{}"
if [ -f "$SCRIPT_DIR/last_alarm.json" ]; then
    if jq -e . "$SCRIPT_DIR/last_alarm.json" >/dev/null 2>&1; then
        last_alarm=$(cat "$SCRIPT_DIR/last_alarm.json")
    fi
fi

if [ -f "$SCRIPT_DIR/alarms.json" ]; then
    if ! jq -e . "$SCRIPT_DIR/alarms.json" >/dev/null 2>&1; then
        echo "Failed to parse JSON in file 'alarms.json'."
        exit 1
    fi
    alarms=$(cat "$SCRIPT_DIR/alarms.json")
fi

if [ -f "$SCRIPT_DIR/aths.json" ]; then
    time_file=$(stat -c %Y "$SCRIPT_DIR/aths.json")
    time_current=$(date +%s)
    time_diff=$((time_file + 300))
    if [ "$time_diff" -lt "$time_current" ] ||
        ! jq -e . "$SCRIPT_DIR/aths.json" >/dev/null 2>&1; then
        rm -f "$SCRIPT_DIR/aths.json"
    else
        ath_prices=$(cat "$SCRIPT_DIR/aths.json")
    fi
fi

# Gets the price according to the symbol parameter and defined time.
get_price() {
    time_gap=$([ -n "$2" ] && date -d "$2 ago" +%s || echo "$time_now")
    lower_bound=$((time_gap - 60))
    upper_bound=$((time_gap + 5))
    value=$(echo "$prices" | jq --argjson lower "$lower_bound" --argjson upper "$upper_bound" \
            '[.[] | select(.timestamp >= $lower and .timestamp <= $upper)]')
    index=$([ -n "$3" ] && echo "$3" || echo "-1")
    [ "$value" != "[]" ] && echo "$value" | jq -r ".[$index].$1"
}

# Updates the list of prices obtained from one of the exchange APIs.
update_price() {
    json_data='[{"timestamp":'"$time_now"
    for currency in $(echo "$exchanges" | jq -r ".$1.api | keys[]"); do
        jq_price=$(echo "$exchanges" | jq -r ".$1.jq_price")
        api_url=$(echo "$exchanges" | jq -r ".$1.api.$currency")
        json=$(curl -s "$api_url")
        price=$(echo "$json" | jq -r "$jq_price?")
        if ! echo "$price" | grep -Eq "$re_price"; then
            return 1
        fi
        price=$(LC_NUMERIC=C printf "%.2f" "$price")
        json_data="${json_data},\"${currency}\":${price}"
    done
    json_data="${json_data}}]"

    prices=$(echo "$prices" | jq ". += $json_data")

    # Filters the JSON and keeps only records with timestamps from the last 24 hours
    old_time=$(date -d "1day ago 1min ago" +%s)
    prices=$(echo "$prices" | jq --argjson cutoff "$old_time" '[.[] | select(.timestamp >= $cutoff)]')

    if ! echo "$prices" | jq -e . >/dev/null 2>&1; then
        echo "Failed to parse JSON, or got false/null."
        exit 1
    fi

    echo "$prices" | jq -c . > "$SCRIPT_DIR/prices.json"
    return 0
}

# Sets the color of the current price compared to the previous price
variation_color() {
    color="\033[37m"
    if [ -n "$2" ]; then
        if [ "$(echo "$1 > $2" | bc -l)" -eq 1 ]; then
            color="\033[32m"
        elif [ "$(echo "$1 < $2" | bc -l)" -eq 1 ]; then
            color="\033[31m"
        fi
    fi
    if [ -n "$3" ]; then
        if [ "$(echo "$1 > $3" | bc -l)" -eq 1 ]; then
            color="\033[1;33m"
        fi
    fi
    printf '%s' "$color"
}

# Lists the price variation over several times.
ls_vartime() {
    ls_title="5m 15m 1h 2h 4h 8h 12h 1d"
    ls_ago="5min 15min 1hour 2hour 4hour 8hour 12hour 1day"
    line_title=""
    line_per=""
    price_now=$(get_price "$curdef")
    i=1
    for title in $ls_title; do
        ago=$(echo "$ls_ago" | cut -d' ' -f"$i")
        price_ago="$(get_price "$curdef" "$ago")"
        if echo "$price_ago" | grep -Eq "$re_price"; then
            len_title=$(printf "%s" "$title" | wc -c)
            left_padding=$(( (8 - len_title) / 2 ))
            right_padding=$(( 8 - (left_padding + len_title) ))
            title_fmt="$(printf '%*s%s%*s' "$left_padding" "" "$title" "$right_padding" "")"

            total_len=$(printf "%s" "$line_title$title_fmt" | wc -c)
            if [ "$total_len" -gt "$tcols" ]; then
                break
            fi

            per_num=$(echo "scale=4; (($price_now / $price_ago - 1) * 100)" | bc)
            color=$(variation_color "$per_num" 0)
            per_num_fmt=$(awk -v per="$per_num" 'BEGIN {printf "%+.2f", per}')"%"
            len_per=$(printf "%s" "$per_num_fmt" | wc -c)
            left_padding=$(( (8 - len_per) / 2 ))
            right_padding=$(( 8 - (left_padding + len_per) ))
            line_title="$line_title$title_fmt"
            line_per="${line_per}${color}$(printf '%*s%s%*s' "$left_padding" "" "$per_num_fmt" "$right_padding" "")"
        fi
        i=$((i + 1))
    done

    if [ -z "$line_title" ]; then
        line_title="(Wait a few minutes)"
    fi
    text="$(printf '%*s' $(( ( tcols - ${#line_title} ) / 2 )) '')\033[37m${line_title}\033[0m\n"
    if [ "${#line_per}" -gt 0 ]; then
        text="${text}$(printf '%*s' $(( ( tcols - ${#line_title} ) / 2 )) '')\033[37m${line_per}\033[0m"
    fi
    echo "$text"
}

# Checks price variations and sounds the alarm according to conditions.
check_alarm() {
    re='^[<>]=? -?[0-9]+(\.[0-9]+)?$'
    echo "$alarms" | jq -c ".[]" | while read -r alarm; do
        condition=$(echo "$alarm" | jq -r ".condition")
        time_ago=$(echo "$condition" | awk '{print $1}')
        variation=$(echo "$condition" | awk '{print $2 " " $3}')
        if ! date -d "$time_ago ago" >/dev/null 2>&1 ||
            ! echo "$variation" | grep -Eq "$re"; then
            echo "Alarm condition '$condition' is invalid."
            exit 1
        fi

        sound=$(echo "$alarm" | jq -r ".sound")
        if ! [ -f "$SCRIPT_DIR/alarms/$sound" ]; then
            printf "Sound file not found:\n-PATH=%s/alarms/%s\n" "$SCRIPT_DIR" "$sound"
            exit 1
        fi

        interval=$(echo "$alarm" | jq -r ".interval")
        last=$(echo "$last_alarm" | jq -r --arg i "$interval" '.[$i]')
        [ "$last" != "null" ] && [ $((time_now - last)) -lt "$interval" ] && continue

        currency=$(echo "$alarm" | jq -r ".currency")
        [ -z "$currency" ] && currency="$curdef"

        price_now=$(get_price "$currency")
        price_ago=$(get_price "$currency" "$time_ago")
        echo "$price_ago" | grep -Eq "$re_price" || continue
        if ! echo "$price_now / $price_ago - 1 $variation" | bc -l | grep -q '^1'; then
            continue
        fi

        nohup play -q "$SCRIPT_DIR/alarms/$sound" >/dev/null 2>&1 &
        last_alarm=$(echo "$last_alarm" | jq --arg i "$interval" --argjson t "$time_now" '.[$i] = $t')
        echo "$last_alarm" | jq -c . > "$SCRIPT_DIR/last_alarm.json"
        break
    done
}

# Calculates columns for ASCII art based on font and number.
calc_figlet_cols() {
    _cfc_font="$1"
    _cfc_price="$2"

    case "$_cfc_font" in
        big) _cfc_fncols=6.9 ;;
        small) _cfc_fncols=6.2 ;;
        *) _cfc_fncols=4 ;;
    esac

    _cfc_only_numbers=$(echo "$_cfc_price" | tr -cd '0-9')
    _cfc_char_length="${#_cfc_only_numbers}"
    awk "BEGIN {print int($_cfc_char_length * $_cfc_fncols + 2)}"
}

exchange_selected=""
for exchange in $(echo "$exchanges" | jq -r "to_entries[] | .key"); do
    if update_price "$exchange"; then
        exchange_selected="$exchange"
        break
    fi
done
if [ -z "$exchange_selected" ]; then
    cat << EOF
Currency values ​​were not found in exchange APIs.
Possible causes:
- APIs are not working
- Your network is offline with the internet
EOF
    exit 1
fi
curdef=$(echo "$exchanges" | jq -r ".${exchange_selected}.api | to_entries | first(.[]).key")

if [ -z "$ath_prices" ]; then
    json=$(curl -s "https://api.coingecko.com/api/v3/coins/bitcoin" | jq -r ".market_data.ath")
    ath_prices="{"
    for currency in $(echo "$exchanges" | jq -r ".${exchange_selected}.api | keys[]"); do
        price=$(echo "$json" | jq -r ".$currency?")
        if echo "$price" | grep -Eq "$re_price"; then
            price=$(LC_NUMERIC=C printf "%.2f" "$price")
        else
            price=""
        fi
        ath_prices="${ath_prices}\"${currency}\":\"${price}\","
    done
    ath_prices="${ath_prices%?}}"

    if ! echo "$ath_prices" | jq -e . >/dev/null 2>&1; then
        echo "Failed to parse JSON, or got false/null."
        exit 1
    fi
fi

body="$(printf '%*s' $(( ( tcols - 16 - ${#exchange_selected} ) / 2 )) '')"
first_char=$(printf '%s' "$exchange_selected" | cut -c1 | tr '[:lower:]' '[:upper:]')
rest=$(printf '%s' "$exchange_selected" | cut -c2-)
body="${body}Bitcoin Price - ${first_char}${rest}\n\n"

# Sets the color of the current dollar price compared to the price 30 seconds ago
price_now=$(get_price "$curdef")
price_ago=$(get_price "$curdef" "0sec" "-2")
price_ath=$(echo "$ath_prices" | jq -r ".${curdef}")
color=$(variation_color "$price_now" "$price_ago" "$price_ath")

# Current dollar price with capital letters
price_formatted=$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')

font_number=0
font_selected=""
for font_name in big small mini; do
    fgt_cols=$(calc_figlet_cols "$font_name" "$price_formatted")
    if [ "$fgt_cols" -lt "$tcols" ]; then
        font_selected="$font_name"
        break
    fi
    font_number=$((font_number + 1))
done

color_suffix=$(printf '%s' "$color" | cut -c6-)
[ "$font_number" -eq 2 ] && body="${body}\n"
body="${body}\033[1;${color_suffix}$(figlet -f "$font_selected" -w "$tcols" -c -m1 "$price_formatted")\033[0m\n"
[ "$font_number" -ge 1 ] && body="${body}\n\n"

# Current others price with small letters
length=3
for currency in $(echo "$exchanges" | jq -r ".${exchange_selected}.api | to_entries[] | .key"); do
    if [ "$currency" = "$curdef" ]; then
        continue
    fi
    small_prices="${small_prices}\033[0m · "
    length=$(( length + 3 ))

    # Sets the color of the current price compared to the price 30 seconds ago
    price_now=$(get_price "${currency}")
    price_ago=$(get_price "${currency}" "0sec" "-2")
    price_ath=$(echo "$ath_prices" | jq -r ".${currency}")
    color=$(variation_color "$price_now" "$price_ago" "$price_ath")

    # Current price with small letters
    currency_uc=$(printf '%s' "$currency" | tr '[:lower:]' '[:upper:]')
    price_fmt=$(awk -v p="$price_now" 'BEGIN {printf "%\047.2f", p}')
    price_formatted="${currency_uc} ${price_fmt}"
    length=$(( length + ${#price_formatted} ))
    small_prices="${small_prices}${color}${price_formatted}"
done
small_prices="${small_prices}\033[0m · "

pad=$(printf '%*s' $(( (tcols - length) / 2 )) "")
body="${body}${pad}${small_prices}"
if [ $font_number -ge 1 ]; then body="${body}\n"; fi

body="${body}\n\n$(ls_vartime)"

ath_news=$ath_prices
for currency in $(echo "$exchanges" | jq -r ".${exchange_selected}.api | keys[]"); do
    price_now=$(get_price "$currency")
    price_ath=$(echo "$ath_prices" | jq -r ".${currency}")
    if [ -z "$price_ath" ] ||
        [ "$(echo "$price_now <= $price_ath" | bc -l)" -eq 1 ]; then
        continue
    fi
    ath_news=$(echo "$ath_news" | jq --arg c "$currency" --arg p "$price_now" '.[$c] = $p')
done
echo "$ath_news" | jq -c . > "$SCRIPT_DIR/aths.json"

if [ "$ath_prices" != "$ath_news" ]; then
    nohup play -q "$SCRIPT_DIR/alarms/win-high-long.mp3" >/dev/null 2>&1 &
elif [ -n "$alarms" ]; then
    check_alarm
fi
printf '%b' "$body"
