#!/usr/bin/env bash

tcols=$(tput cols)

feehigh=$(bitcoin-cli -rpcwait estimatesmartfee 2 "economical" | jq .feerate)
feehigh=$(awk -v fee="$feehigh" 'BEGIN {printf "%.8f", fee}')
feehigh=$(echo "$feehigh * 100000" | bc)
feehigh=$(awk -v fee="$feehigh" 'BEGIN {printf "%.0f", fee}')" sat/vB"

feemedium=$(bitcoin-cli -rpcwait estimatesmartfee 4 "economical" | jq .feerate)
feemedium=$(awk -v fee="$feemedium" 'BEGIN {printf "%.8f", fee}')
feemedium=$(echo "$feemedium * 100000" | bc)
feemedium=$(awk -v fee="$feemedium" 'BEGIN {printf "%.0f", fee}')" sat/vB"

feelow=$(bitcoin-cli -rpcwait estimatesmartfee 8 "economical" | jq .feerate)
feelow=$(awk -v fee="$feelow" 'BEGIN {printf "%.8f", fee}')
feelow=$(echo "$feelow * 100000" | bc)
feelow=$(awk -v fee="$feelow" 'BEGIN {printf "%.0f", fee}')" sat/vB"

feenoprio=$(bitcoin-cli -rpcwait estimatesmartfee 16 "economical" | jq .feerate)
feenoprio=$(awk -v fee="$feenoprio" 'BEGIN {printf "%.8f", fee}')
feenoprio=$(echo "$feenoprio * 100000" | bc)
feenoprio=$(awk -v fee="$feenoprio" 'BEGIN {printf "%.0f", fee}')" sat/vB"

echo -e "$(printf '%*s' $(( ($tcols - 16) / 2 )) '')Transaction Fees\n"
echo -e "$(printf '%*s' $(( ($tcols - 4) / 2 )) '')\033[0mHigh"
echo -e "$(printf '%*s' $(( ($tcols - ${#feehigh}) / 2 )) '')\033[35m$feehigh\n"
echo -e "$(printf '%*s' $(( ($tcols - 6) / 2 )) '')\033[0mMedium"
echo -e "$(printf '%*s' $(( ($tcols - ${#feemedium}) / 2 )) '')\033[35m$feemedium\n"
echo -e "$(printf '%*s' $(( ($tcols - 3) / 2 )) '')\033[0mLow"
echo -e "$(printf '%*s' $(( ($tcols - ${#feelow}) / 2 )) '')\033[35m$feelow\n"
echo -e "$(printf '%*s' $(( ($tcols - 11) / 2 )) '')\033[0mNo Priority"
echo -e "$(printf '%*s' $(( ($tcols - ${#feenoprio}) / 2 )) '')\033[35m$feenoprio"
