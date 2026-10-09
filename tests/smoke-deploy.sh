#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
temp=$(mktemp -d /tmp/gadi-pixi-smoke.XXXXXX)
cleanup() { find "$temp" -type d -exec chmod u+w {} +; rm -rf -- "$temp"; }
trap cleanup EXIT
root="$temp/release-root"
stage="$temp/stage"
mkdir -p "$stage/artifact/bin"
mkdir -p "$root"
printf 'pixi-jobfs-v1\n' > "$root/.pixi-jobfs-release-root"
ln -s "$repo" "$stage/repo"
printf '0\n' > "$stage/status"
printf '#!/bin/sh\nexit 0\n' > "$stage/artifact/bin/pixi"
chmod 755 "$stage/artifact/bin/pixi"
tar -C "$stage" -czf "$stage/artifact/archive.tar.gz" status
( cd "$stage/artifact" && sha256sum archive.tar.gz > archive.tar.gz.sha256 && sha256sum bin/pixi > pixi.sha256 )
first="$(printf 'a%.0s' {1..40})"
second="$(printf 'b%.0s' {1..40})"
for sha in "$first" "$second"; do
    ALLOW_TEST_ROOT=1 GADI_DEPLOY_ROOT="$root" GADI_RUN_DIR="$stage" RELEASE_SHA="$sha" \
      bash "$repo/scripts/deploy.sh"
done
test "$(readlink "$root/modulefiles/are-pixi/current")" = "r-$second"
cp "$stage/artifact/archive.tar.gz.sha256" "$temp/good.sha256"
printf '%064d  archive.tar.gz\n' 0 > "$stage/artifact/archive.tar.gz.sha256"
if ALLOW_TEST_ROOT=1 GADI_DEPLOY_ROOT="$root" GADI_RUN_DIR="$stage" RELEASE_SHA="$(printf 'c%.0s' {1..40})" \
    bash "$repo/scripts/deploy.sh" > "$temp/rejected-output" 2>&1; then
    echo 'Corrupt archive was accepted' >&2; exit 1
fi
test "$(readlink "$root/modulefiles/are-pixi/current")" = "r-$second"
mv "$temp/good.sha256" "$stage/artifact/archive.tar.gz.sha256"
ALLOW_TEST_ROOT=1 GADI_DEPLOY_ROOT="$root" bash "$repo/scripts/rollback.sh" "r-$first"
test "$(readlink "$root/modulefiles/are-pixi/current")" = "r-$first"
test -f "$root/releases/r-$second/archive.tar.gz"
printf 'local deploy and rollback smoke passed\n'
