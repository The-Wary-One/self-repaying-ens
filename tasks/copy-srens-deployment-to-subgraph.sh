#!/usr/bin/env bash

jq ".abi" ./deployments/SelfRepayingENS.json > ../srens-subgraph/abis/SelfRepayingENS.json
