# ACCESS-Analysis-Pixi

ACCESS-Analysis-Pixi is a flexible Python analysis environment for JupyterLab on Gadi's Australian Research Environment (ARE). It provides a shared base of commonly used scientific packages. In your own ARE session, you can add the packages your analysis needs with [Pixi](https://pixi.sh/) without changing the shared base for anyone else.

The base includes Python 3.12, Jupyter kernel support, NumPy, SciPy, xarray, Matplotlib, scikit-image, NetworkX, and Zarr. [`pixi.toml`](pixi.toml) defines the base packages, and [`pixi.lock`](pixi.lock) records their exact versions. Packages available for Linux through conda-forge or PyPI can be added when your session has network access and their dependencies are compatible.

## Start an ARE session

In the ARE JupyterLab form:

1. Choose a project that can read the installed Pixi release. Include that release's `gdata` project and any projects containing your data in **Storage**.
2. Request at least **8 GB JOBFS**. Leave the Python/Conda virtual environment fields and **Pre-script** empty.
3. Set **Module directories** to the installed release's `modulefiles` directory. Set **Modules** to `are-pixi/current`. Ask your project administrator for the module directory if you do not have it.
4. Start JupyterLab and select the **Python 3.12 (Pixi JOBFS)** kernel for your notebook.

The module copies the base environment into your allocation's JOBFS at startup. Your notebook then uses that private copy. If the kernel is missing, check the ARE job log and `$PBS_JOBFS/are-pixi-py312/startup.log` for the startup error.

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

Run `bash scripts/check.sh` for local manifest, pin, and shell checks. The protected Gadi checks exercise the package build and offline installation.
