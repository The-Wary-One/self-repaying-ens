#!/usr/bin/env bash

source .env

# Set -e AFTER sourcing .env because this file doesn't exist in the CI pipeline.
set -e

# 30 gwei.
gasprice=30000000000

# Run the test with the given gas price.
forge test \
    --gas-price "$gasprice" \
    -vvv \
    --gas-report
