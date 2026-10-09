#!/usr/bin/env bash
# Executed by ARE directly or by the modulefile during module load.
set -Eeuo pipefail
: "${PBS_JOBFS:?Allocate at least 8 GB JOBFS in ARE}"
: "${PBS_JOBID:?ARE PBS allocation required}"
: "${CONFIG_FILE:?ARE Jupyter config required}"
[[ -f $CONFIG_FILE ]] || { echo "Missing ARE config: $CONFIG_FILE" >&2; exit 1; }
release=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
work="$PBS_JOBFS/are-pixi-py312"
project="$work/project"
kernel_root="$work/kernels/share/jupyter/kernels"
kernel=are-pixi-py312
mkdir -p "$work/bin" "$work/tmp" "$work/matplotlib" "$work/xdg-cache" "$work/pixi-home" "$kernel_root"
exec > >(tee -a "$work/startup.log") 2>&1
printf 'Pixi release=%s job=%s\n' "$release" "$PBS_JOBID"
( cd "$release" && sha256sum -c archive.tar.gz.sha256 && sha256sum -c pixi.sha256 )
cp "$release/bin/pixi-jobfs-wrapper" "$work/bin/pixi"
chmod 755 "$work/bin/pixi"
tar -xzf "$release/archive.tar.gz" -C "$work" --no-same-owner --no-same-permissions
export PIXI_CACHE_DIR="$work/cache" PIXI_HOME="$work/pixi-home" TMPDIR="$work/tmp" XDG_CACHE_HOME="$work/xdg-cache"
export PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
PIXI_OFFLINE=true "$release/bin/pixi" install --locked --manifest-path "$project/pixi.toml"
"$release/bin/import-check.sh" "$project/.pixi/envs/default/bin/python"
"$project/.pixi/envs/default/bin/python" -m ipykernel install --prefix "$work/kernels" \
  --name "$kernel" --display-name 'Python 3.12 (Pixi JOBFS)'
"$project/.pixi/envs/default/bin/python" - "$work" "$kernel_root" "$kernel" "$CONFIG_FILE" "$release" <<'PY'
import json, os, pathlib, sys
work, kernel_root, kernel, config_file, release = sys.argv[1:]
project = pathlib.Path(work) / 'project'
spec = pathlib.Path(kernel_root) / kernel / 'kernel.json'
data = json.loads(spec.read_text())
data.setdefault('env', {}).update({
    'PIXI_CACHE_DIR': f'{work}/cache',
    'PIXI_HOME': f'{work}/pixi-home',
    'PIXI_JOBFS_PROJECT': str(project),
    'PIXI_REAL': f'{release}/bin/pixi',
    'TMPDIR': f'{work}/tmp',
    'MPLCONFIGDIR': f'{work}/matplotlib',
    'XDG_CACHE_HOME': f'{work}/xdg-cache',
    'PYTHONNOUSERSITE': '1', 'PYTHONPATH': '', 'PYTHONHOME': '',
    'PATH': f'{work}/bin:{release}/bin:' + os.environ.get('PATH', ''),
})
spec.write_text(json.dumps(data, indent=2) + '\n')
config = pathlib.Path(config_file)
with config.open('a') as fh:
    fh.write('\n# Current allocation Pixi kernel\n')
    fh.write('import os as _pixi_os\n')
    for key, value in {
        'PIXI_CACHE_DIR': f'{work}/cache', 'PIXI_HOME': f'{work}/pixi-home',
        'PIXI_JOBFS_PROJECT': str(project),
        'PIXI_REAL': f'{release}/bin/pixi', 'TMPDIR': f'{work}/tmp',
        'MPLCONFIGDIR': f'{work}/matplotlib', 'XDG_CACHE_HOME': f'{work}/xdg-cache',
    }.items():
        fh.write(f'_pixi_os.environ[{key!r}] = {value!r}\n')
    fh.write(f'_pixi_jupyter = {str(pathlib.Path(kernel_root).parent)!r}\n')
    fh.write('_pixi_old = _pixi_os.environ.get("JUPYTER_PATH")\n')
    fh.write('_pixi_os.environ["JUPYTER_PATH"] = _pixi_jupyter + (_pixi_os.pathsep + _pixi_old if _pixi_old else "")\n')
    fh.write(f'_pixi_os.environ["PATH"] = {work + "/bin:" + release + "/bin:"!r} + _pixi_os.environ.get("PATH", "")\n')
print('kernel_python=' + data['argv'][0])
print('jupyter_config=' + str(config))
PY
