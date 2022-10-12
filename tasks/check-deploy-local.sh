#!/usr/bin/env bash
set -e

source .env

# Check the last Mainnet fork deployment.
forge script script/Toolbox.s.sol:Toolbox \
    -s "check()" \
    -f "http://localhost:8545" \
    --skip-simulation \
    -vvv
