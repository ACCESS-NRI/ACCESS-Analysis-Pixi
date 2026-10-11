#!/usr/bin/env bash
# Run from a staged checkout on a Gadi login node.
set -euo pipefail
: "${GADI_RUN_DIR:?} ${GADI_PROJECT:?} ${GADI_STORAGE:?} ${GADI_BUILD_QUEUE:?}"
[[ $GADI_RUN_DIR =~ ^/scratch/[a-z0-9]+/[A-Za-z0-9_/-]+$ ]] || { echo 'GADI_RUN_DIR must be under a project scratch directory' >&2; exit 2; }
[[ $GADI_PROJECT =~ ^[a-z0-9]+$ && $GADI_BUILD_QUEUE =~ ^[a-z0-9]+$ ]] || exit 2
[[ $GADI_STORAGE =~ ^[a-z0-9/+]+$ ]] || exit 2
cd "$GADI_RUN_DIR"
test -d repo && test ! -e status
mkdir -p logs
set +e
qsub -Wblock=true -N pixi_jobfs -P "$GADI_PROJECT" -q "$GADI_BUILD_QUEUE" \
  -l "ncpus=1,mem=8GB,walltime=02:00:00,storage=$GADI_STORAGE" \
  -v "GADI_RUN_DIR=$GADI_RUN_DIR" -o "$GADI_RUN_DIR/logs" -e "$GADI_RUN_DIR/logs" \
  "$GADI_RUN_DIR/repo/scripts/build-test.pbs" &
qsub_pid=$!
set -e
while kill -0 "$qsub_pid" 2>/dev/null; do
  printf 'Waiting for PBS build at %s UTC; Gadi logs: %s/logs\n' "$(date -u +%H:%M:%S)" "$GADI_RUN_DIR"
  sleep 30
done
set +e
wait "$qsub_pid"
qsub_rc=$?
set -e
for log in "$GADI_RUN_DIR"/logs/*; do
  if [[ -f $log ]]; then
    printf '\n--- %s ---\n' "$log"
    cat "$log"
  fi
done
if [[ ! -f status ]]; then
  echo "PBS did not write status (qsub exit $qsub_rc); inspect $GADI_RUN_DIR/logs" >&2
  exit 1
fi
read -r job_rc < status
[[ $job_rc == 0 && $qsub_rc == 0 ]] || { echo "PBS failed: qsub=$qsub_rc job=$job_rc" >&2; exit 1; }
test -s artifact/archive.tar.gz && test -s artifact/archive.tar.gz.sha256
printf 'Gadi build/test succeeded: %s\n' "$GADI_RUN_DIR"
