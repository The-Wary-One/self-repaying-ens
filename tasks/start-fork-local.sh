#!/usr/bin/env bash
set -e

source .env

# Start a local anvil instance forked from Mainnet
anvil \
    --fork-url "${RPC_MAINNET}" \
    --fork-block-number "${BLOCK_NUMBER_MAINNET}"
