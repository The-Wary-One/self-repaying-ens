#!/usr/bin/env bash
set -e

source .env

# Deploy the SRENS using the first anvil account.
forge script script/DeploySRENS.s.sol:DeploySRENS \
    -f "http://localhost:8545" \
    --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" \
    --broadcast \
    -vvv
