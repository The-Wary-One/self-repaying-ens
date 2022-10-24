#!/usr/bin/env bash
set -e

source .env

# Check the amount of days is supplied.
if [[ $# -eq 0 ]] ; then
    echo "No amount of days supplied."
    exit 1
fi

# Calculate amount of days we want to fast forward.
days=$1
seconds=$(( days * 24 * 60 * 60 ))

# Fast forward by n days amount of seconds.
cast rpc anvil_setBlockTimestampInterval $seconds > /dev/null

# Mine the block
cast rpc anvil_mine > /dev/null
