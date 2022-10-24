#!/usr/bin/env bash
set -e

source .env

# Check the name is supplied.
if [ -z "$1" ] ; then
    echo "No name supplied."
    exit 1
fi

name=$1

# Subscribe to renew `name`.
forge script script/Toolbox.s.sol:Toolbox \
    -f "http://localhost:8545" \
    --private-key "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" \
    -s "subscribe(string)" "$name" \
    --broadcast
