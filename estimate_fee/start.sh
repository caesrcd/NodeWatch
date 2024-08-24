#!/usr/bin/env bash

cols=$(tput cols)

feehigh=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq .feerate)
feehigh=$(awk -v fee="$feehigh" 'BEGIN {printf "%.8f", fee}')
feehigh=$(echo "$feehigh * 100000" | bc)
feehigh=$(awk -v fee="$feehigh" "BEGIN {printf \"%.0f\", fee}")" sat/vB"

feemedium=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq .feerate)
feemedium=$(awk -v fee="$feemedium" 'BEGIN {printf "%.8f", fee}')
feemedium=$(echo "$feemedium * 100000" | bc)
feemedium=$(awk -v fee="$feemedium" "BEGIN {printf \"%.0f\", fee}")" sat/vB"

feelow=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq .feerate)
feelow=$(awk -v fee="$feelow" 'BEGIN {printf "%.8f", fee}')
feelow=$(echo "$feelow * 100000" | bc)
feelow=$(awk -v fee="$feelow" "BEGIN {printf \"%.0f\", fee}")" sat/vB"

feenoprio=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq .feerate)
feenoprio=$(awk -v fee="$feenoprio" 'BEGIN {printf "%.8f", fee}')
feenoprio=$(echo "$feenoprio * 100000" | bc)
feenoprio=$(awk -v fee="$feenoprio" "BEGIN {printf \"%.0f\", fee}")" sat/vB"

echo -e "$(printf '%*s' $(( ($cols - 16) / 2 )) '')Transaction Fees\n"
echo -e "$(printf '%*s' $(( ($cols - 4) / 2 )) '')\033[0mHigh"
echo -e "$(printf '%*s' $(( ($cols - ${#feehigh}) / 2 )) '')\033[35m$feehigh\n"
echo -e "$(printf '%*s' $(( ($cols - 6) / 2 )) '')\033[0mMedium"
echo -e "$(printf '%*s' $(( ($cols - ${#feemedium}) / 2 )) '')\033[35m$feemedium\n"
echo -e "$(printf '%*s' $(( ($cols - 3) / 2 )) '')\033[0mLow"
echo -e "$(printf '%*s' $(( ($cols - ${#feelow}) / 2 )) '')\033[35m$feelow\n"
echo -e "$(printf '%*s' $(( ($cols - 11) / 2 )) '')\033[0mNo Priority"
echo -e "$(printf '%*s' $(( ($cols - ${#feenoprio}) / 2 )) '')\033[35m$feenoprio"
