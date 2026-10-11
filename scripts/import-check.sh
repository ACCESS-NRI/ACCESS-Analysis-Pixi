#!/usr/bin/env bash
set -euo pipefail
"${1:?Python path required}" - <<'PY'
import sys
import ipykernel, numpy, scipy, xarray, matplotlib, skimage, networkx, zarr
assert sys.version_info[:2] == (3, 12), sys.version
print('imports passed:', sys.executable)
PY
