#!/usr/bin/env bash
set -e

source .env

# Create an Alchemix alETH account.
forge script script/Toolbox.s.sol:Toolbox \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "depositUnderlying()" \
    --skip-simulation \
    --broadcast

# Approve the last deployed srens contract to mint alETH debt.
forge script script/Toolbox.s.sol:Toolbox \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "approve()" \
    --skip-simulation \
    --broadcast
