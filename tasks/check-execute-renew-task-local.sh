#!/usr/bin/env bash
set -e

source .env

# Check the name is supplied.
if [ -z "$1" ]
then
    echo "No name supplied."
    exit 1
fi
# Check the base fee is supplied.
if [ -z "$2" ]
then
    echo "No base fee supplied."
    exit 1
fi

name=$1
# In wei.
baseFee=$(($2 * 1000000000))
# The second anvil account address.
subscriber=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
# Get the last local deployment.
address=$(jq -r ".transactions[0].contractAddress" ./broadcast/DeploySRENS.s.sol/1/run-latest.json)

# Set the baseFee.
echo "🤖 Set the block base fee to $2 gwei..."
cast rpc anvil_setNextBlockBaseFeePerGas "$baseFee" > /dev/null

# Call the checker function to know if we can execute the renew task.
echo "🏃 Call checker with $name $subscriber..."
result=$(cast call "$address" \
    --gas-price "$baseFee" \
    "checker(string,address)(bool,bytes)" "$name" "$subscriber")
result=($result)
isReady=${result[0]}

# Check the name renew base fee floor.
nameBaseFeeFloor=$(cast call "$address" "getVariableMaxBaseFee(string)(uint256)" "$name")
echo "🔍 $name base fee floor: $nameBaseFeeFloor wei."

if [ "$isReady" == false ]
then
    echo "🔴 $name cannot be renewed: $(cast --to-ascii "${result[1]}")"
    exit 0
fi
echo "📢 $name can be renewed."

# Call the exec function on the Gelato Ops contract.
echo "👷 Execute the renew task for $name $subscriber..."

# Give 1 ETH to the Gelato contract to pay for the transaction.
cast rpc anvil_setBalance 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6 1000000000000000000 > /dev/null
# Impersonate the Gelato contract.
cast rpc anvil_impersonateAccount 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6 > /dev/null

execData=$(cast calldata "renew(string,address)" "$name" "$subscriber")
moduleData=$(forge script script/ToolboxLocal.s.sol:ToolboxLocal \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "getModuleData(address,string,address)" "$address" "$name" "$subscriber" \
    --silent \
    --json | jq -rc '.returns."0".value' | tr -d "[:space:]")

estimated=$(cast estimate 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F \
    --from 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6 \
    "exec(address,address,bytes,(uint8[],bytes[]),uint256,address,bool,bool)" \
    "$address" \
    "$address" \
    "$execData" \
    "$moduleData" \
    55000000000000000 \
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE \
    false \
    true)

res=$(cast send 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F \
    --from 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6 \
    --gas-price "$baseFee" \
    --gas-limit "$estimated" \
    --json \
    "exec(address,address,bytes,(uint8[],bytes[]),uint256,address,bool,bool)" \
    "$address" \
    "$address" \
    "$execData" \
    "$moduleData" \
    "$estimated" \
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE \
    false \
    true)

# Stop impersonating the Gelato contract.
cast rpc anvil_stopImpersonatingAccount 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6 > /dev/null

status=$(echo "$res" | jq -r ".status")

if [ "$status" == 0x0 ]
then
    echo "🔴 tx failed!"
    cast run "$(echo "$res" | jq -r ".transactionHash")"
    exit 1
fi
                  #
echo "✅ $name renewed!"
