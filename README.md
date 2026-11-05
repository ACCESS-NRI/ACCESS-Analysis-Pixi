# ACCESS-Analysis-Pixi

ACCESS-Analysis-Pixi is a flexible Python analysis environment for JupyterLab on Gadi's Australian Research Environment (ARE) and single-node PBS batch jobs. Analysis3 used SquashFS to solve the inode problem for its large Conda environment. Here, the installed analysis environment lives on fast JOBFS, which does not count against the shared filesystem's inode quota. JOBFS is cleared when the job ends, so each job's environment is disposable and no SquashFS layer is needed.

Everyone starts from the same base of scientific packages. You can then tailor your own dependency stack with [Pixi](https://pixi.sh/), adding packages for your analysis without changing the shared base or another user's environment.

The base includes Python 3.12, Jupyter kernel support, NumPy, SciPy, xarray, Matplotlib, scikit-image, NetworkX, and Zarr. [`pixi.toml`](pixi.toml) defines the base packages, and [`pixi.lock`](pixi.lock) records their exact versions. Packages available for Linux through conda-forge or PyPI can be added when your session has network access and their dependencies are compatible.

## Start an ARE session

In the ARE JupyterLab form:

1. Choose a project that can read the installed Pixi release. Include that release's `gdata` project and any projects containing your data in **Storage**.
2. Request at least **8 GB JOBFS**. Leave the Python/Conda virtual environment fields and **Pre-script** empty.
3. Set **Module directories** to `/g/data/xp65/public/modules` and **Modules** to `are-pixi/current`.
4. Start JupyterLab and select the **Python 3.12 (Pixi JOBFS)** kernel for your notebook.

The module unpacks the base onto your allocation's JOBFS and installs it there. Your notebook then uses that private copy. If the kernel is missing, check the ARE job log and `$PBS_JOBFS/are-pixi-py312/startup.log` for the startup error.

## Run a PBS batch job

Use [`examples/analysis.pbs`](examples/analysis.pbs) as a starting point. Set your compute project, resources, and all required storage projects, including `gdata/xp65` for the release. Request at least **8 GB JOBFS**, save the script beside your `analysis.py` on persistent storage, and submit it with `qsub analysis.pbs`.

The job loads the same module used in ARE:

```bash
set -euo pipefail
module use /g/data/xp65/public/modules
module load are-pixi/current
python analysis.py
```

In an ordinary PBS job, the module prepares the released base offline and puts its Python and command-line tools on `PATH`. No Jupyter configuration or kernel is needed. Keep `set -e` so a failed module load stops the job before your analysis runs. Startup diagnostics go to the job log and `$PBS_JOBFS/are-pixi-py312/startup.log`. In ARE, the presence of `CONFIG_FILE` selects the existing Jupyter setup instead, preserving the server's Python.

Each new job starts from the shared base. Reloading the same release within a job reuses its environment and preserves additions; switching releases requires a new job. For reproducible runs, use a versioned module such as `are-pixi/r-<commit SHA>` instead of `current`. Save results outside JOBFS before the job ends.

Batch jobs set `PIXI_OFFLINE=true`: ordinary Gadi compute queues cannot download missing packages ([NCI queue guidance](https://opus.nci.org.au/spaces/Help/pages/236880996/Queue%2BStructure%2Bon%2BGadi...)). Packages added in another ARE session are not included automatically. Reproducing a customised environment offline requires its manifest, lockfile, and complete package cache; this release supports the shared base and does not yet provide a custom-environment export/import workflow.

This batch setup supports **one compute node**. Multi-node MPI or distributed Dask jobs need the environment prepared separately on every node because JOBFS is node-local; loading the module on the first node does not prepare the others.

## Add packages for your analysis

Run `pixi add` in an ARE terminal:

```bash
pixi add seaborn
pixi add --pypi humanize
```

In a notebook cell, prefix the command with `!`, for example `!pixi add seaborn`. The first terminal command above adds a conda-forge package; `--pypi` adds a PyPI package. The included `pixi` wrapper directs these commands to your session's JOBFS environment, so you do not need to edit this repository or create a separate project. If you add or replace a package that is already imported, restart the notebook kernel before using the new version.

Additions need network access and must be available for the platform with compatible dependencies. ARE sessions are expected to have network access for this step; ordinary PBS jobs often do not. The pinned base is installed offline, so starting an ARE session does not depend on a package download.

## Keep or share your additions

Each ARE allocation starts from the released base. Packages you add, and the resulting `pixi.toml` and `pixi.lock`, live on that allocation's temporary JOBFS and disappear when the job ends. They do not change the shared release or another user's session.

If you want a record of your package choices, copy `$PIXI_JOBFS_PROJECT/pixi.toml` and `$PIXI_JOBFS_PROJECT/pixi.lock` to persistent project storage before the job ends. You can use those files in a future Pixi project. To make a package part of the shared default, propose a change to this repository's manifest and lock file through a pull request. Once that change is reviewed and deployed, new ARE sessions using `are-pixi/current` receive the updated base; running sessions keep their existing environment.

## For maintainers

The shared base is built from the checked-in manifest and lock file, tested on Gadi, and deployed as a versioned release. The `are-pixi/current` module points to the active release; older versioned modules remain available. See the [deployment and rollback guide](docs/deployment.md) for GitHub Actions setup, Gadi requirements, release verification, and base package updates.

Run `bash scripts/check.sh` for local manifest, pin, and shell checks. Run `bash tests/runtime.sh` with Environment Modules installed (or set `MODULES_INIT` to its Bash initialization script) to test batch and ARE startup using a small fake package installer. The protected Gadi checks exercise the real package build and offline installation through the batch module.
