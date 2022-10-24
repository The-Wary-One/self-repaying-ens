#!/usr/bin/env bash
set -e

source .env

# Check the name is supplied.
if [ -z "$1" ] ; then
    echo "No name supplied."
    exit 1
fi

name=$1

# Make a commitment to register `name` to the ETHControllerRegistrar contract.
forge script script/Toolbox.s.sol:Toolbox \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "commitName(string)" "$name" \
    --skip-simulation \
    --broadcast

# Wait 1 day.
./tasks/fast-forward-time-local.sh 1

# Register the ENS name.
forge script script/Toolbox.s.sol:Toolbox \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "registerName(string)" "$name" \
    --skip-simulation \
    --broadcast
