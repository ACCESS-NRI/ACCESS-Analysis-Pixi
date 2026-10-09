#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config/pins.env
sha256sum -c <(printf '%s  %s\n%s  %s\n' "$LOCK_SHA256" pixi.lock "$MANIFEST_SHA256" pixi.toml)
for script in scripts/*.sh runtime/*.sh runtime/pixi-jobfs-wrapper scripts/*.pbs; do
    bash -n "$script"
done
python3 - <<'PY'
import pathlib
import tomllib
manifest = tomllib.loads(pathlib.Path('pixi.toml').read_text())
assert manifest['workspace']['platforms'] == ['linux-64']
assert set(manifest['dependencies']) == {'python', 'ipykernel', 'numpy', 'scipy', 'xarray', 'matplotlib', 'scikit-image', 'networkx', 'zarr'}
lock = pathlib.Path('pixi.lock').read_text()
assert lock.startswith('version: 7\n') and 'linux-64' in lock
runtime = pathlib.Path('runtime/are-prescript.sh').read_text()
start = runtime.index("<<'PY'\n") + len("<<'PY'\n")
end = runtime.index('\nPY', start)
compile(runtime[start:end], 'runtime/are-prescript.sh:embedded-python', 'exec')
print('manifest, lock and shell syntax OK')
PY
