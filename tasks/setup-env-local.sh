#!/usr/bin/env bash
set -e

source .env

# Check anvil is running
echo "👮 Check if anvil is running a mainnet fork..."
if [[ $(cast chain-id) -ne 1 ]]
then
    echo "🔴 Anvil must run a mainnet fork!"
    exit 1
fi

# Deploy SRENS locally
echo "🚀 Deploy the SelfRepayingENS contract..."
./tasks/deploy-srens-local.sh > /dev/null

# Whitelist the SRENS.
echo "🔓 Whitelist the SelfRepayinsENS contract..."
./tasks/whitelist-srens-local.sh > /dev/null

# Register a ENS name
echo "💵 Register the \"self-repaying\" .eth name..."
./tasks/register-name-local.sh "self-repaying" > /dev/null

# Copy the Deployment file to the frontend. Only useful when working on the frontend !
#echo "🚚 Copy the srens deployment file to the frontend project..."
#./tasks/copy-srens-deployment-to-front.sh > /dev/null

echo "✅ Done!"
