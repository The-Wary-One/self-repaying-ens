#!/usr/bin/env bash
set -e

source .env

# Check the last Mainnet fork deployment.
forge script script/CheckDeploy.s.sol:CheckDeploy \
    -f "http://localhost:8545" \
    -vvv
