# Deploy ACCESS-Analysis-Pixi from GitHub to Gadi

This is the setup and first-release runbook. The GitHub repository and Gadi production root have not been created by this local scaffold. The ARE module remains named `are-pixi`; `ACCESS-Analysis-Pixi` is the repository name. Keep `GADI_DEPLOY_ENABLED` unset until the PR build and permissions are verified.

## 1. Publish the repository safely

Create an empty GitHub repository named `ACCESS-Analysis-Pixi` under the chosen owner. Do not ask GitHub to add a README, license, or `.gitignore` during creation; this local repository already has commits. Choose the license in a reviewed change. Then, from this local directory, replace `OWNER` and run:

```bash
cd /home/romain/PROJECTS/PIXI_ANALYSIS4/ACCESS-Analysis-Pixi
bash scripts/check.sh
bash tests/smoke-deploy.sh
bash tests/failure-status.sh
git remote add origin git@github.com:OWNER/ACCESS-Analysis-Pixi.git
git push -u origin main
```

The initial push runs `local-check`. The Gadi job is skipped because the repository variable `GADI_DEPLOY_ENABLED` is not yet `true`. The [GitHub guide to publishing an existing repository](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github) describes the same remote-and-push sequence.

## 2. Prepare restricted Gadi identities and directories

Choose the build PBS project and an internet-capable queue. Confirm that the chosen queue can fetch conda-forge packages; the pilot built successfully in an ARE allocation, while its `copyq` request with JOBFS did not schedule. This workflow requests scratch storage and no JOBFS for the build. NCI requires a PBS `storage` directive covering every scratch and gdata project used by the job; the build reads the existing pilot Pixi binary on `gdata/xp65` and writes under the chosen scratch project ([NCI PBS Python guidance](https://opus.nci.org.au/spaces/Help/pages/248840704/Python...)).

- Give the **PR identity** permission to submit PBS jobs, write only its dedicated scratch staging tree, and read the pinned pilot binary at `/g/data/xp65/public/apps/pixi-pilot/jobfs-packed-env-test/bin/pixi`. It must have no write permission to the production release root.
- Give the **production identity** the same build access plus write access to one new dedicated release root. Confirm group and ACL access so ARE users can read releases and modulefiles. Do not alter any other `xp65` path.
- Create a fresh production root matching `/g/data/<release-project>/public/apps/<name>`; `ACCESS-Analysis-Pixi` is a suitable `<name>`. Ensure that root did not previously belong to another application. Inside it, create `.pixi-jobfs-release-root` with the single line `pixi-jobfs-v1`. The deploy and rollback scripts refuse an unmarked root or one that is a symlink.
- Reserve distinct staging roots under `/scratch/<build-project>/...` for PR and production runs. The workflow creates a unique run directory below each root and leaves it for log review and a later retention cleanup.

Arrange approved SSH access from GitHub-hosted runners to Gadi for each identity. Verify Gadi's SSH host key through a trusted source and store its known-hosts line in GitHub; the workflow does not trust a key fetched during its run. Use separate SSH keys for PR and production. Do not put private keys or tokens in this repository.

## 3. Configure GitHub environments

In **Settings → Environments**, create `gadi-pr` and `gadi-production`. Add required reviewers to both; enable prevent self-review if appropriate. Restrict `gadi-production` to `main`. The workflow uses `gadi-pr` for PRs and `gadi-production` for main pushes and manual releases. GitHub holds environment secrets until its protection rules pass ([environment setup](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)).

Set these **environment secrets separately in each environment**:

| Secret | Value |
| --- | --- |
| `GADI_HOST` | Approved Gadi SSH hostname, usually `gadi.nci.org.au` |
| `GADI_USER` | The corresponding restricted Gadi account |
| `GADI_SSH_KEY` | That account's private SSH key |
| `GADI_KNOWN_HOSTS` | Verified SSH known-hosts entry for `GADI_HOST` |

Set these **environment variables**:

| Variable | PR and production value |
| --- | --- |
| `GADI_STAGE_ROOT` | A dedicated `/scratch/<build-project>/...` directory; use separate PR and production roots |
| `GADI_PROJECT` | PBS project code authorised for the identity |
| `GADI_STORAGE` | PBS storage resources, for example `scratch/iq82+gdata/xp65` when authorised for both |
| `GADI_BUILD_QUEUE` | Queue verified to permit the online Pixi build |
| `GADI_DEPLOY_ROOT` | Production only: the new marked release root |

The workflow validates the value shapes before opening SSH. Use paths without spaces. At the **repository** variable level, leave `GADI_DEPLOY_ENABLED` unset for now. If the repository is private, confirm the GitHub plan supports required reviewers for environments before relying on this gate ([GitHub availability](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)).

## 4. Gate PRs and prove the Gadi build

Protect `main` in **Settings → Rules → Rulesets** or branch protection: require a PR and approving review, block direct pushes and force pushes, and require the `local-check` and `gadi` checks. If GitHub does not yet list those checks, open one in-repository trial PR, let the checks run, and then make them required before merging. The PR account must be limited to scratch because the PR's scripts are what the Gadi job executes. Fork PRs fail the local gate and must be moved to a reviewed branch in this repository before a Gadi test.

For the trial PR, approve the `gadi-pr` environment request after reviewing the workflow and code. A successful Gadi check means the PBS job built the archive from the checked-in lock, unpacked it to a second prefix, installed with `PIXI_OFFLINE=true`, and passed the Python import check. Inspect its scratch `logs/`, `status`, archive checksum, and GitHub job result. A missing or nonzero PBS status fails the check. GitHub's [branch protection guidance](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) covers required reviews and status checks.

## 5. Make the first release

Once the PR test, Gadi permissions, production root and GitHub protection are verified, set the **repository variable** `GADI_DEPLOY_ENABLED` to `true`. In **Actions → ACCESS-Analysis-Pixi build and release → Run workflow**, choose `main` and run it. Approve the `gadi-production` environment request after reviewing the commit. Manual runs are available because the workflow declares `workflow_dispatch` ([GitHub manual-run guide](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)).

The production job rebuilds and tests the checked-in lock in its own scratch tree, then publishes `<GADI_DEPLOY_ROOT>/releases/r-<full-main-commit-SHA>` and atomically points `<GADI_DEPLOY_ROOT>/modulefiles/are-pixi/current` at that version. It does not copy the PR artifact. Verify on Gadi:

```bash
readlink "$GADI_DEPLOY_ROOT/modulefiles/are-pixi/current"
module use "$GADI_DEPLOY_ROOT/modulefiles"
module display are-pixi/current
```

Then launch an ARE JupyterLab session with the release project in Storage, at least 8 GB JOBFS, module directory `<GADI_DEPLOY_ROOT>/modulefiles`, module `are-pixi/current`, and an empty Pre-script field. Select `Python 3.12 (Pixi JOBFS)`, check the scientific imports, and try one disposable `pixi add` in the session. ARE additions live on that job's JOBFS and do not update the released base. Check the ARE job log if the kernel is missing; a failed module setup may leave the Jupyter server running without the kernel.

## 6. Updates and rollback

For a base package change, edit `pixi.toml`, regenerate `pixi.lock` with the pinned Pixi binary/version, update `LOCK_SHA256` and `MANIFEST_SHA256` in `config/pins.env`, and submit a PR. After checks, review and merge, the main push automatically makes a new `r-<SHA>` release, subject to production environment approval. Existing ARE jobs keep their current JOBFS environment; new jobs using `are-pixi/current` get the new release. Older versioned modules remain available.

To roll back, log in with the production identity, set `GADI_DEPLOY_ROOT`, and run the script stored in the active release:

```bash
active=$(readlink "$GADI_DEPLOY_ROOT/modulefiles/are-pixi/current")
bash "$GADI_DEPLOY_ROOT/releases/$active/bin/rollback.sh" r-<previous-full-commit-SHA>
readlink "$GADI_DEPLOY_ROOT/modulefiles/are-pixi/current"
```

Rollback only repoints `current`; it does not delete releases or change already running ARE sessions. Set `GADI_DEPLOY_ENABLED` to a value other than `true` to stop new production jobs while investigating. It does not cancel a job that has already passed its production approval.
