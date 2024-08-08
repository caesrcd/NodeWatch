#!/usr/bin/env bash

feehigh=$(bitcoin-cli -rpcwait estimatesmartfee 1 "economical" | jq .feerate)
feehigh=$(echo "$feehigh * 100000" | bc | sed "s/\./,/g")

feemedium=$(bitcoin-cli -rpcwait estimatesmartfee 3 "economical" | jq .feerate)
feemedium=$(echo "$feemedium * 100000" | bc | sed "s/\./,/g")

feelow=$(bitcoin-cli -rpcwait estimatesmartfee 5 "economical" | jq .feerate)
feelow=$(echo "$feelow * 100000" | bc | sed "s/\./,/g")

feenoprio=$(bitcoin-cli -rpcwait estimatesmartfee 1000 "economical" | jq .feerate)
feenoprio=$(echo "$feenoprio * 100000" | bc | sed "s/\./,/g")

echo -e "$(printf '%*s' $(( (20 - 16) / 2 )) '')Transaction Fees\n"
echo -e "$(printf '%*s' $(( (20 - 4) / 2 )) '')\033[0mHigh"
echo -e "$(printf '%*s' $(( (20 - 8) / 2 )) '')\033[35m$(printf '%.0f' $feehigh) sat/vB\n"
echo -e "$(printf '%*s' $(( (20 - 6) / 2 )) '')\033[0mMedium"
echo -e "$(printf '%*s' $(( (20 - 8) / 2 )) '')\033[35m$(printf '%.0f' $feemedium) sat/vB\n"
echo -e "$(printf '%*s' $(( (20 - 3) / 2 )) '')\033[0mLow"
echo -e "$(printf '%*s' $(( (20 - 8) / 2 )) '')\033[35m$(printf '%.0f' $feelow) sat/vB\n"
echo -e "$(printf '%*s' $(( (20 - 11) / 2 )) '')\033[0mNo Priority"
echo -e "$(printf '%*s' $(( (20 - 8) / 2 )) '')\033[35m$(printf '%.0f' $feenoprio) sat/vB"
