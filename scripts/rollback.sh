#!/usr/bin/env bash
# Atomically repoint the public module alias to an existing immutable release.
set -euo pipefail
: "${GADI_DEPLOY_ROOT:?}"
release="${1:?Pass an existing r-<40 hex SHA> release}"
[[ $release =~ ^r-[0-9a-f]{40}$ ]] || exit 2
if [[ ${ALLOW_TEST_ROOT:-} == 1 ]]; then
    [[ $GADI_DEPLOY_ROOT == /tmp/* ]] || exit 2
else
    [[ $GADI_DEPLOY_ROOT =~ ^/g/data/[a-z0-9]+/public/apps/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || exit 2
fi
[[ $GADI_DEPLOY_ROOT != *pixi-pilot* ]] || exit 2
root="$GADI_DEPLOY_ROOT"
[[ ! -L $root && -f $root/.pixi-jobfs-release-root ]] || exit 2
[[ $(cat "$root/.pixi-jobfs-release-root") == pixi-jobfs-v1 ]] || exit 2
module_dir="$root/modulefiles/are-pixi"
test -f "$module_dir/$release" && test -d "$root/releases/$release"
( cd "$root/releases/$release" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
exec 9>"$root/.deploy.lock"
flock -x 9
temp="$module_dir/.current-$$"
trap 'rm -f -- "$temp"' EXIT
ln -s "$release" "$temp"
mv -Tf -- "$temp" "$module_dir/current"
printf 'current=%s\n' "$release"
