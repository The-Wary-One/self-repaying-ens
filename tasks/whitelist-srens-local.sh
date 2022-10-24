#!/usr/bin/env bash
set -e

source .env

# Get the last local deployment.
address=$(jq -r ".transactions[0].contractAddress" ./broadcast/DeploySRENS.s.sol/1/run-latest.json)

# Impersonate the Alchemist owner.
cast rpc anvil_impersonateAccount 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 > /dev/null

# Whitelist the last deployed SRENS contract.
cast send 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653 \
    --from 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 \
    "add(address)" "$address"

# Stop impersonating the Alchemist owner.
cast rpc anvil_stopImpersonatingAccount 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 > /dev/null
