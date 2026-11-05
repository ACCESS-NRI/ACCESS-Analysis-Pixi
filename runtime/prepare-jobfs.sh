#!/usr/bin/env bash
# Install the released base for either an ARE kernel or a PBS batch job.
set -Eeuo pipefail
: "${PBS_JOBFS:?Allocate at least 8 GB JOBFS in your PBS job}"
: "${PBS_JOBID:?A PBS allocation is required}"
release=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work="$PBS_JOBFS/are-pixi-py312"
project="$work/project"
mkdir -p "$work"
exec > >(tee -a "$work/startup.log") 2>&1
exec 9>"$work/.prepare.lock"
flock -x 9

# Reloading a module must not unpack the base over a user's package additions.
if [[ -f $work/.ready ]]; then
    [[ $(cat "$work/.ready") == "$release" ]] || {
        echo 'A different Pixi release is already prepared in this JOBFS; start a new job to switch releases.' >&2
        exit 1
    }
    [[ -x $project/.pixi/envs/default/bin/python && -f $project/pixi.toml && -f $project/pixi.lock ]] || {
        echo 'The prepared Pixi environment is incomplete; start a new job.' >&2
        exit 1
    }
    printf 'Reusing Pixi release=%s job=%s\n' "$release" "$PBS_JOBID"
    exit 0
fi

printf 'Preparing Pixi release=%s job=%s\n' "$release" "$PBS_JOBID"
( cd "$release" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
mkdir -p "$work/bin" "$work/tmp" "$work/matplotlib" "$work/xdg-cache" "$work/pixi-home"
cp "$release/bin/pixi-jobfs-wrapper" "$work/bin/pixi"
chmod 755 "$work/bin/pixi"
tar -xzf "$release/archive.tar.gz" -C "$work" --no-same-owner --no-same-permissions
export PIXI_CACHE_DIR="$work/cache" PIXI_HOME="$work/pixi-home" TMPDIR="$work/tmp"
export XDG_CACHE_HOME="$work/xdg-cache" MPLCONFIGDIR="$work/matplotlib" PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
PIXI_OFFLINE=true "$release/bin/pixi" install --locked --manifest-path "$project/pixi.toml"
"$release/bin/import-check.sh" "$project/.pixi/envs/default/bin/python"
printf '%s\n' "$release" > "$work/.ready"
