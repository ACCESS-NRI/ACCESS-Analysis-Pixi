# ACCESS-Analysis-Pixi

This repository prepares a separately managed successor to the local Pixi pilot (`are-jobfs-packed-env-pilot/`). `ACCESS-Analysis-Pixi` is the repository name; the existing ARE module interface remains `are-pixi`. It has not been deployed. Its scripts refuse to publish into the pilot tree. Follow the [GitHub-to-Gadi deployment guide](docs/deployment.md) before enabling production.

## What is pinned

- `pixi.toml` (SHA-256 `5734ce23a58fed1f6b8a2a9b357f1a4917d8a4846a94c03ad6cf8927f2bf053c`) and the real 9 October 2026 pilot `pixi.lock` (SHA-256 `a8c914ba19774fb04e2160ec50dbd94873650b686ca54f7a09917e9acdd76358`). Both hashes were also verified against the copies inside the pilot archive. Refresh both together in a reviewed PR; update `config/pins.env` after checking the new files.
- The [official Pixi 0.70.2 Linux binary](https://github.com/prefix-dev/pixi/releases/download/v0.70.2/pixi-x86_64-unknown-linux-musl), SHA-256 `e10db390cc6d68f7a16ec6960fb3a8f9fcd346edf9e41a1e45f58fb44d80df95`. GitHub Actions downloads and verifies it, then stages it on Gadi. Every release includes its own copy.
- Pilot cache archive `/g/data/xp65/public/apps/pixi-pilot/jobfs-packed-env-test/pixi-py312-cache-v1.tar.gz`, SHA-256 `7aeea9c21d6030500df2d6f7237a359172a0fb345b312e794acb2a196f724b16`, recorded as provenance only. Each CI run builds a fresh archive from the checked-in lock. Nothing reads or writes the pilot archive during CI.

The pilot archive was 496,932,877 bytes and its offline relocation passed on Gadi. Those results are evidence for this design, not a test of this new repository.

## Release flow

1. A PR runs a local manifest, lock hash, and shell syntax check. A protected `gadi-pr` environment then stages that exact checkout under `/scratch/<project>/...`, builds with `pixi install --locked`, and tests the archive by unpacking into a second prefix and installing with `PIXI_OFFLINE=true`. It imports Python 3.12 and the scientific packages there. The PR credential must have scratch write access and **no production write access**. Fork PRs fail the local gate until moved to a reviewed branch in the repository.
2. Branch protection requires the local and Gadi checks and reviews before merge. Once the repository variable `GADI_DEPLOY_ENABLED` is `true`, a push to protected `main` repeats the build and offline test for the merged commit under a separate protected `gadi-production` environment, then deploys `r-<full commit SHA>` into its own immutable directory. The first release can also be started manually on `main`. It never promotes a PR build.
3. Deployment verifies archive and Pixi checksums, copies the runtime and lock, creates a versioned modulefile, and atomically points `modulefiles/are-pixi/current` at it. Existing versions are kept. `rollback.sh` moves only that pointer to a previously verified release.

The production root must be a **new, dedicated** `/g/data/<project>/public/apps/<name>` directory. Never set it to the pilot directory or an existing application directory. PR jobs write only to scratch; the GitHub production job requires the enable variable, a configured production environment, and its approval.

The reference [ACCESS-Analysis-Conda repository](https://github.com/ACCESS-NRI/ACCESS-Analysis-Conda) describes PR builds in temporary locations and post-merge deployment. Its current [PR workflow](https://github.com/ACCESS-NRI/ACCESS-Analysis-Conda/blob/main/.github/workflows/pull_request.yml) calls its [build workflow](https://github.com/ACCESS-NRI/ACCESS-Analysis-Conda/blob/main/.github/workflows/build.yml), while its separate test job is currently commented out; its [push workflow](https://github.com/ACCESS-NRI/ACCESS-Analysis-Conda/blob/main/.github/workflows/push_to_main.yml) calls [deploy](https://github.com/ACCESS-NRI/ACCESS-Analysis-Conda/blob/main/.github/workflows/deploy.yml). This scaffold makes the offline test mandatory and rechecks on merge.

## GitHub and Gadi setup before enabling

1. Create the `ACCESS-Analysis-Pixi` repository and choose a license. Protect `main`: require a PR, review of workflow and script changes, and both `local-check` and `gadi` status checks. Disable direct pushes except authorised maintainers. Set GitHub environments `gadi-pr` and `gadi-production` with required reviewers. Limit production environment use to `main`. The PR approval protects SSH credentials from unreviewed code; use distinct Gadi accounts or permissions so the PR key cannot write the release root. Keep the repository variable `GADI_DEPLOY_ENABLED` unset until the Gadi setup is ready.
2. In **each** environment set secrets `GADI_HOST`, `GADI_USER`, `GADI_SSH_KEY`, and `GADI_KNOWN_HOSTS` (the verified host key, not `ssh-keyscan` at job time). Set variables `GADI_STAGE_ROOT`, `GADI_PROJECT`, `GADI_STORAGE`, and `GADI_BUILD_QUEUE`. In production also set `GADI_DEPLOY_ROOT`. Example stage root: `/scratch/iq82/ci/pixi-jobfs`; the PBS build needs its scratch project in `GADI_STORAGE`. The selected identity needs project membership, PBS submission rights, and scratch quota. Production additionally needs write access to only its dedicated root. Check directory group/ACL policy with the project owner before enabling; the scripts use world-readable files and do not change unrelated ACLs. An administrator must create the new empty root and a `.pixi-jobfs-release-root` file containing exactly `pixi-jobfs-v1`; deploy and rollback refuse an unmarked or symlinked root.
3. Confirm a queue in `GADI_BUILD_QUEUE` where the build job can reach conda-forge (and any configured proxy). The pilot `copyq` request could not schedule with JOBFS and the successful build used an ARE allocation. This scaffold requests **no JOBFS for its build** and uses scratch for the cache. If the chosen queue cannot fetch packages, the build fails before deployment; select an approved internet-capable build route. NCI's [PBS Python guidance](https://opus.nci.org.au/spaces/Help/pages/248840704/Python...) requires a `storage` request for every scratch or gdata project a job accesses.
4. Trial a PR with the restricted account, inspect the scratch logs and status, then merge only after the offline test is green. Trial the production identity against a disposable dedicated root before selecting the real root. A successful PBS job removes its temporary `work/` tree to avoid exhausting scratch inode quota; the logs, status, checkout, and archive remain for audit. Arrange retention for those remaining CI directories and for failed runs.

The `qsub -Wblock=true` response is not trusted alone: `build-test.pbs` writes its exit code to `status` on every ordinary exit, and `gadi-run.sh` requires both qsub and the PBS script to report zero. Missing status fails the workflow. A hard killed job may leave no status; inspect `logs/` and rerun with a new stage directory.

## ARE use after a reviewed deployment

In ARE JupyterLab choose a project with read access to the release root, request `storage=gdata/<release-project>` plus any notebook data projects, and at least 8 GB JOBFS. Leave Python/Conda virtual environment fields empty. Set **Module directories** to `<GADI_DEPLOY_ROOT>/modulefiles` and **Modules** to `are-pixi/current` (or an immutable `are-pixi/r-<SHA>`). Leave **Pre-script** empty. ARE's normal JupyterLab server remains separate; the module calls `are-prescript.sh` after `PBS_JOBFS` and `CONFIG_FILE` exist. Select `Python 3.12 (Pixi JOBFS)`.

Startup verifies both checksums, unpacks the cache onto that allocation's JOBFS, runs a locked offline install, checks imports, and writes its kernelspec to JOBFS only. The module errors on setup failure; ARE may still start a server without this kernel, so treat a missing kernel as a failed launch and inspect the ARE job log and `$PBS_JOBFS/are-pixi-py312/startup.log`.

In the kernel or ARE terminal, `pixi add seaborn` and `pixi add --pypi humanize` target the session's JOBFS manifest through the included wrapper. The manifest, lock, cache and installed packages are disposable with the job. Save the JOBFS `project/pixi.toml` and `project/pixi.lock` to persistent storage if session additions must be reproduced. Do not write additions into the released cache. A running Python kernel may need restarting after replacing an imported package. Ordinary PBS jobs without internet cannot fetch packages for `pixi add`; they can only install the pinned base from the cache unless packages are separately staged. Internet access in an ARE session is an explicit operating assumption for additions.

## Rollback and verification

From an authorised Gadi account, set `GADI_DEPLOY_ROOT` to the dedicated root and run the rollback script in the active release:

```bash
active=$(readlink "$GADI_DEPLOY_ROOT/modulefiles/are-pixi/current")
bash "$GADI_DEPLOY_ROOT/releases/$active/bin/rollback.sh" r-<previous-full-commit-SHA>
readlink "$GADI_DEPLOY_ROOT/modulefiles/are-pixi/current"
```

Rollback does not change an existing ARE session. Launch a new session to use the restored alias. A versioned module remains available for precise reproducibility. Failed releases are not garbage-collected automatically.

Local checks: `bash scripts/check.sh`. They do not exercise Pixi package downloads, PBS, Modules, ARE, filesystem ACLs, or Jupyter startup. Those are first verified by the protected Gadi PR run and a later ARE smoke session.
