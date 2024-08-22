#!/usr/bin/env bash

cols=$(tput cols)

feehigh=$(bitcoin-cli -rpcwait estimatesmartfee 1 "economical" | jq .feerate)
feehigh=$(echo "$feehigh * 100000" | bc)
feehigh=$(awk "BEGIN {printf \"%.0f\", $feehigh}")" sat/vB"

feemedium=$(bitcoin-cli -rpcwait estimatesmartfee 3 "economical" | jq .feerate)
feemedium=$(echo "$feemedium * 100000" | bc)
feemedium=$(awk "BEGIN {printf \"%.0f\", $feemedium}")" sat/vB"

feelow=$(bitcoin-cli -rpcwait estimatesmartfee 5 "economical" | jq .feerate)
feelow=$(echo "$feelow * 100000" | bc)
feelow=$(awk "BEGIN {printf \"%.0f\", $feelow}")" sat/vB"

feenoprio=$(bitcoin-cli -rpcwait estimatesmartfee 1000 "economical" | jq .feerate)
feenoprio=$(echo "$feenoprio * 100000" | bc)
feenoprio=$(awk "BEGIN {printf \"%.0f\", $feenoprio}")" sat/vB"

echo -e "$(printf '%*s' $(( ($cols - 16) / 2 )) '')Transaction Fees\n"
echo -e "$(printf '%*s' $(( ($cols - 4) / 2 )) '')\033[0mHigh"
echo -e "$(printf '%*s' $(( ($cols - ${#feehigh}) / 2 )) '')\033[35m$feehigh\n"
echo -e "$(printf '%*s' $(( ($cols - 6) / 2 )) '')\033[0mMedium"
echo -e "$(printf '%*s' $(( ($cols - ${#feemedium}) / 2 )) '')\033[35m$feemedium\n"
echo -e "$(printf '%*s' $(( ($cols - 3) / 2 )) '')\033[0mLow"
echo -e "$(printf '%*s' $(( ($cols - ${#feelow}) / 2 )) '')\033[35m$feelow\n"
echo -e "$(printf '%*s' $(( ($cols - 11) / 2 )) '')\033[0mNo Priority"
echo -e "$(printf '%*s' $(( ($cols - ${#feenoprio}) / 2 )) '')\033[35m$feenoprio"
