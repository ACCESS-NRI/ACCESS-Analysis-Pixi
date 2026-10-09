#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
temp=$(mktemp -d /tmp/gadi-pixi-failure.XXXXXX)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/repo/config"
printf 'PIXI_SOURCE=/missing-pixi\nPIXI_SHA256=0000000000000000000000000000000000000000000000000000000000000000\nPIXI_VERSION=0\n' > "$temp/repo/config/pins.env"
touch "$temp/repo/pixi.lock"
if GADI_RUN_DIR="$temp" PBS_JOBID=local-test bash "$repo/scripts/build-test.pbs" > "$temp/output" 2>&1; then
    echo 'Unexpected PBS build success' >&2; exit 1
fi
test -f "$temp/status"
read -r status < "$temp/status"
[[ $status != 0 ]]
printf 'PBS failure status propagated: %s\n' "$status"
