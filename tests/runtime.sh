#!/usr/bin/env bash
# Exercise real Environment Modules with a tiny fake Pixi/package installation.
# Scientific imports and the real cache are checked by scripts/build-test.pbs.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
temp=$(mktemp -d /tmp/access-analysis-pixi-runtime.XXXXXX)
trap 'rm -rf -- "$temp"' EXIT

if ! type module >/dev/null 2>&1; then
    source "${MODULES_INIT:-/usr/share/modules/init/bash}"
fi
module purge
unset CONFIG_FILE PBS_JOBFS PBS_JOBID PYTHONPATH PYTHONHOME
export TEST_PYTHON
TEST_PYTHON=$(command -v python3)
export TEST_INSTALLS="$temp/installs"
export TEST_IMPORTS="$temp/imports"
export TEST_PYTHON_SHIM="$temp/python"
: > "$TEST_INSTALLS"
: > "$TEST_IMPORTS"
release="$temp/release"
mkdir -p "$release/bin" "$temp/contents/project" "$temp/contents/cache" "$temp/modulefiles/are-pixi"
cp "$repo/runtime/prepare-jobfs.sh" "$repo/runtime/are-prescript.sh" "$repo/runtime/pixi-jobfs-wrapper" "$release/bin/"
cp "$repo/pixi.toml" "$repo/pixi.lock" "$temp/contents/project/"
printf 'cached package fixture\n' > "$temp/contents/cache/package"
tar -C "$temp/contents" -czf "$release/archive.tar.gz" cache project
cat > "$release/bin/pixi" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == "install --locked --manifest-path "* ]]
[[ $PIXI_OFFLINE == true && $PYTHONNOUSERSITE == 1 ]]
[[ ! ${PYTHONPATH+x} && ! ${PYTHONHOME+x} ]]
[[ -f $PIXI_CACHE_DIR/package && -d $PIXI_HOME && -d $TMPDIR && -d $MPLCONFIGDIR ]]
printf 'install\n' >> "$TEST_INSTALLS"
[[ ${TEST_FAIL_INSTALL:-0} != 1 ]] || exit 17
manifest=$4
mkdir -p "${manifest%/*}/.pixi/envs/default/bin"
cp "$TEST_PYTHON_SHIM" "${manifest%/*}/.pixi/envs/default/bin/python"
ln -sf python "${manifest%/*}/.pixi/envs/default/bin/python3"
SH
cat > "$TEST_PYTHON_SHIM" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -m && ${2:-} == ipykernel ]]; then
    "$TEST_PYTHON" - "$0" "$@" <<'PY'
import json, pathlib, sys
args = sys.argv[2:]
root = pathlib.Path(args[args.index('--prefix') + 1])
name = args[args.index('--name') + 1]
spec = root / 'share/jupyter/kernels' / name / 'kernel.json'
spec.parent.mkdir(parents=True, exist_ok=True)
spec.write_text(json.dumps({'argv': [sys.argv[1], '-m', 'ipykernel_launcher', '-f', '{connection_file}'],
                           'display_name': args[args.index('--display-name') + 1]}))
PY
else
    exec "$TEST_PYTHON" "$@"
fi
SH
cat > "$release/bin/import-check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'imports\n' >> "$TEST_IMPORTS"
[[ ${TEST_FAIL_IMPORT:-0} != 1 ]] || exit 18
"$1" -c 'import os; assert os.environ["PYTHONNOUSERSITE"] == "1"'
SH
chmod 755 "$release/bin/"* "$TEST_PYTHON_SHIM"
(
    cd "$release"
    sha256sum archive.tar.gz > archive.tar.gz.sha256
    sha256sum bin/pixi > pixi.sha256
)
sed "s|@RELEASE@|$release|g" "$repo/runtime/modulefile.tcl.in" > "$temp/modulefiles/are-pixi/test"
module use "$temp/modulefiles"

# Display and login-shell loads must not prepare an environment.
module display are-pixi/test
if module load are-pixi/test; then
    echo 'Module loaded outside PBS' >&2; exit 1
fi
test ! -s "$TEST_INSTALLS"

(
    export PBS_JOBID=batch-test PBS_JOBFS="$temp/batch"
    export PYTHONPATH=/unwanted/python PYTHONHOME=/unwanted/home
    module display are-pixi/test
    test ! -d "$PBS_JOBFS"
    module load are-pixi/test
    test "$(command -v python)" = "$PIXI_JOBFS_PROJECT/.pixi/envs/default/bin/python"
    test "$(command -v python3)" = "$PIXI_JOBFS_PROJECT/.pixi/envs/default/bin/python3"
    test "$(command -v pixi)" = "$PBS_JOBFS/are-pixi-py312/bin/pixi"
    test "$PIXI_REAL" = "$release/bin/pixi"
    test "$PIXI_OFFLINE" = true
    test -z "${PYTHONPATH+x}${PYTHONHOME+x}"
    python -c 'import os; assert os.environ["PIXI_CACHE_DIR"].startswith(os.environ["PBS_JOBFS"])'
    test ! -e "$PBS_JOBFS/are-pixi-py312/kernels"
    test -s "$PBS_JOBFS/are-pixi-py312/startup.log"
    printf '\n# user addition\n' >> "$PIXI_JOBFS_PROJECT/pixi.toml"
    cp "$PIXI_JOBFS_PROJECT/pixi.toml" "$temp/added.toml"
    module unload are-pixi/test
    [[ $(command -v python || true) != "$PBS_JOBFS/are-pixi-py312/"* ]]
    test -z "${PIXI_JOBFS_PROJECT+x}${PIXI_REAL+x}${PIXI_OFFLINE+x}"
    module load are-pixi/test
    cmp "$temp/added.toml" "$PIXI_JOBFS_PROJECT/pixi.toml"
    test "$(wc -l < "$TEST_INSTALLS")" -eq 1
    test "$(wc -l < "$TEST_IMPORTS")" -eq 1
)

# A failed load must terminate a normal set -e batch script before its payload.
export PBS_JOBID=failure-test PBS_JOBFS="$temp/failure" TEST_FAIL_INSTALL=1
if bash -e -c 'module load are-pixi/test; touch "$PBS_JOBFS/payload-ran"'; then
    echo 'Batch script continued after installation failed' >&2; exit 1
fi
test ! -e "$PBS_JOBFS/payload-ran"
test ! -e "$PBS_JOBFS/are-pixi-py312/.ready"
unset TEST_FAIL_INSTALL
(
    module load are-pixi/test
    test -f "$PBS_JOBFS/are-pixi-py312/.ready"
)

(
    export PBS_JOBFS="$temp/import-failure" TEST_FAIL_IMPORT=1
    if module load are-pixi/test; then
        echo 'Module accepted failed imports' >&2; exit 1
    fi
    test ! -e "$PBS_JOBFS/are-pixi-py312/.ready"
    test -z "${PIXI_JOBFS_PROJECT+x}"
)

# Check both checksum failures before the installer can run.
for target in archive.tar.gz bin/pixi; do
    cp "$release/$target" "$temp/original"
    printf 'corruption\n' >> "$release/$target"
    (
        export PBS_JOBFS="$temp/corrupt-${target##*/}"
        before=$(wc -l < "$TEST_INSTALLS")
        if module load are-pixi/test; then
            echo "Module accepted corrupt $target" >&2; exit 1
        fi
        test "$(wc -l < "$TEST_INSTALLS")" -eq "$before"
        test ! -e "$PBS_JOBFS/are-pixi-py312/.ready"
    )
    cp "$temp/original" "$release/$target"
done

# Another release must not overwrite the live environment or its additions.
cp -a "$release" "$temp/other-release"
(
    export PBS_JOBFS="$temp/batch"
    if "$temp/other-release/bin/prepare-jobfs.sh"; then
        echo 'A different release overwrote an existing environment' >&2; exit 1
    fi
    cmp "$temp/added.toml" "$PBS_JOBFS/are-pixi-py312/project/pixi.toml"
)

(
    export PBS_JOBID=are-test PBS_JOBFS="$temp/are" CONFIG_FILE="$temp/jupyter.py"
    : > "$CONFIG_FILE"
    server_path=$PATH
    module load are-pixi/test
    test "$PATH" = "$server_path"
    test -z "${PIXI_JOBFS_PROJECT+x}"
    "$TEST_PYTHON" - "$release" <<'PY'
import json, os, pathlib, sys
work = pathlib.Path(os.environ['PBS_JOBFS']) / 'are-pixi-py312'
spec = json.loads((work / 'kernels/share/jupyter/kernels/are-pixi-py312/kernel.json').read_text())
assert spec['argv'][0] == str(work / 'project/.pixi/envs/default/bin/python')
assert spec['display_name'] == 'Python 3.12 (Pixi JOBFS)'
assert spec['env']['PIXI_REAL'] == sys.argv[1] + '/bin/pixi'
assert spec['env']['PYTHONPATH'] == spec['env']['PYTHONHOME'] == ''
assert spec['env']['PIXI_JOBFS_PROJECT'] == str(work / 'project')
config = pathlib.Path(os.environ['CONFIG_FILE'])
exec(compile(config.read_text(), str(config), 'exec'), {})
assert os.environ['PIXI_JOBFS_PROJECT'] == str(work / 'project')
assert os.environ['JUPYTER_PATH'].split(':')[0] == str(work / 'kernels/share/jupyter')
assert os.environ['PATH'].split(':')[0] == str(work / 'bin')
assert 'PIXI_OFFLINE' not in os.environ  # ARE additions retain online access.
PY
    module unload are-pixi/test
    test "$PATH" = "$server_path"
)
(
    export PBS_JOBFS="$temp/invalid-are" CONFIG_FILE="$temp/missing-config"
    if module load are-pixi/test; then
        echo 'Module ignored a missing ARE config' >&2; exit 1
    fi
    test ! -d "$PBS_JOBFS"
)
printf 'PBS and ARE runtime integration checks passed\n'
