#!/bin/bash -e

if [[ -e ./commands/lib.sh ]]; then
    source ./commands/lib.sh
else
    source .flow-lib
fi

args=()
for arg in "$@"; do
    args+=("$arg")
done
async "${args[@]}"
echo $!
