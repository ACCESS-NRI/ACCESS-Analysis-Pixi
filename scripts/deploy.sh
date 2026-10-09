#!/usr/bin/env bash
# Run only after this commit's Gadi build and offline test have passed.
set -euo pipefail
: "${GADI_DEPLOY_ROOT:?} ${GADI_RUN_DIR:?} ${RELEASE_SHA:?}"
[[ $RELEASE_SHA =~ ^[0-9a-f]{40}$ ]] || { echo 'RELEASE_SHA must be a full Git SHA' >&2; exit 2; }
if [[ ${ALLOW_TEST_ROOT:-} == 1 ]]; then
    [[ $GADI_DEPLOY_ROOT == /tmp/* ]] || exit 2
else
    [[ $GADI_DEPLOY_ROOT =~ ^/g/data/[a-z0-9]+/public/apps/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || exit 2
fi
[[ $GADI_DEPLOY_ROOT != *pixi-pilot* ]] || { echo 'Pilot tree is protected' >&2; exit 2; }
[[ $GADI_RUN_DIR =~ ^/scratch/[a-z0-9]+/[A-Za-z0-9_/-]+$ || ${ALLOW_TEST_ROOT:-} == 1 ]] || exit 2
read -r job_rc < "$GADI_RUN_DIR/status"
[[ $job_rc == 0 ]] || { echo 'Build/test did not pass' >&2; exit 1; }
artifact="$GADI_RUN_DIR/artifact"
( cd "$artifact" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
release="r-$RELEASE_SHA"
root="$GADI_DEPLOY_ROOT"
release_dir="$root/releases/$release"
module_dir="$root/modulefiles/are-pixi"
[[ ! -L $root && -f $root/.pixi-jobfs-release-root ]] || { echo 'Dedicated release root is not initialized' >&2; exit 2; }
[[ $(cat "$root/.pixi-jobfs-release-root") == pixi-jobfs-v1 ]] || exit 2
mkdir -p "$root/releases" "$module_dir"
exec 9>"$root/.deploy.lock"
flock -x 9
temp="$root/releases/.tmp-$release-$$"
module_tmp="$module_dir/.tmp-$release-$$"
link_tmp="$module_dir/.current-$$"
cleanup() { rm -rf -- "$temp"; rm -f -- "$module_tmp" "$link_tmp"; }
trap cleanup EXIT
if [[ ! -e $release_dir ]]; then
    mkdir -p "$temp/bin"
    install -m 0644 "$artifact/archive.tar.gz" "$artifact/archive.tar.gz.sha256" "$artifact/pixi.sha256" "$temp/"
    install -m 0755 "$artifact/bin/pixi" "$temp/bin/pixi"
    install -m 0755 "$GADI_RUN_DIR/repo/runtime/are-prescript.sh" "$temp/bin/are-prescript.sh"
    install -m 0755 "$GADI_RUN_DIR/repo/runtime/pixi-jobfs-wrapper" "$temp/bin/pixi-jobfs-wrapper"
    install -m 0755 "$GADI_RUN_DIR/repo/scripts/import-check.sh" "$temp/bin/import-check.sh"
    install -m 0644 "$GADI_RUN_DIR/repo/pixi.toml" "$GADI_RUN_DIR/repo/pixi.lock" "$temp/"
    ( cd "$temp" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
    chmod -R a-w "$temp"
    mv -T -- "$temp" "$release_dir"
else
    cmp "$artifact/archive.tar.gz.sha256" "$release_dir/archive.tar.gz.sha256"
    cmp "$artifact/pixi.sha256" "$release_dir/pixi.sha256"
    ( cd "$release_dir" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
fi
sed "s|@RELEASE@|$release_dir|g" "$GADI_RUN_DIR/repo/runtime/modulefile.tcl.in" > "$module_tmp"
chmod 0444 "$module_tmp"
if [[ -e $module_dir/$release ]]; then
    cmp "$module_tmp" "$module_dir/$release"
else
    mv -T -- "$module_tmp" "$module_dir/$release"
fi
ln -s "$release" "$link_tmp"
mv -Tf -- "$link_tmp" "$module_dir/current"
printf 'promoted=%s module=%s\n' "$release_dir" "$module_dir/current"
