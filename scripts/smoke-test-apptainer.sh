#!/usr/bin/env bash

# Run the end-to-end smoke test with explicit Apptainer /work and /data binds.
#
# Usage:
#   ./scripts/smoke-test-apptainer.sh
#   WORK_DIR=/scratch/hep-work \
#     APPTAINER_DATA_DIR=/scratch/hep-data \
#     ./scripts/smoke-test-apptainer.sh
#
# Environment:
#   WORK_DIR            Host directory bound to /work (default: repository).
#   APPTAINER_DATA_DIR  Initialized host directory bound to /data
#                       (default: repository/.data/apptainer).
#   APPTAINER_IMAGE     SIF to test (default: repository/.data/hep-env-local.sif).
#   SMOKE_EVENTS        Number of generated events (default: 1000).
#   SMOKE_KEEP_WORK     Set to 1 to retain hep-env-smoke output (CI use).
#
# APPTAINER_DATA_DIR must contain the .hep-env-initialized stamp created by
# the Makefile's data initialization. This wrapper never overwrites data.

set -euo pipefail

usage() {
  sed -n '3,20s/^# \{0,1\}//p' "$0"
}

case ${1:-} in
-h | --help)
  usage
  exit 0
  ;;
'') ;;
*)
  usage >&2
  exit 2
  ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$script_dir/.." && pwd -P)
work_dir=$(realpath -m -- "${WORK_DIR:-$repo_dir}")
apptainer_data_dir=$(realpath -m -- \
  "${APPTAINER_DATA_DIR:-$repo_dir/.data/apptainer}")
apptainer_image=$(realpath -m -- \
  "${APPTAINER_IMAGE:-$repo_dir/.data/hep-env-local.sif}")
smoke_events=${SMOKE_EVENTS:-1000}
keep_work=${SMOKE_KEEP_WORK:-0}
smoke_host_dir=$work_dir/hep-env-smoke
created_work_dir=0
cleanup_smoke_dir=0

cleanup() {
  local status=$1
  local cleanup_status=0

  trap - EXIT
  set +e
  if [[ $keep_work != 1 && $cleanup_smoke_dir == 1 &&
    -d $smoke_host_dir ]]; then
    if ! rm -rf -- "$smoke_host_dir"; then
      echo "Could not remove smoke output: $smoke_host_dir" >&2
      cleanup_status=1
    fi
  fi
  if [[ $keep_work != 1 && $created_work_dir == 1 ]]; then
    rmdir -- "$work_dir" 2>/dev/null || true
  fi
  if ((status == 0 && cleanup_status != 0)); then
    status=$cleanup_status
  fi
  exit "$status"
}

trap 'cleanup "$?"' EXIT

if [[ ! $smoke_events =~ ^[1-9][0-9]*$ ]]; then
  echo "SMOKE_EVENTS must be a positive integer: $smoke_events" >&2
  exit 2
fi
if [[ $keep_work != 0 && $keep_work != 1 ]]; then
  echo "SMOKE_KEEP_WORK must be 0 or 1: $keep_work" >&2
  exit 2
fi
if [[ $work_dir == / ]]; then
  echo 'WORK_DIR must not be the filesystem root' >&2
  exit 2
fi
command -v apptainer >/dev/null
command -v timeout >/dev/null
[[ -f $apptainer_image ]] || {
  echo "Apptainer image not found: $apptainer_image" >&2
  exit 1
}
[[ -d $apptainer_data_dir ]] || {
  echo "Apptainer data directory not found: $apptainer_data_dir" >&2
  exit 1
}
[[ -f $apptainer_data_dir/.hep-env-initialized ]] || {
  echo "Apptainer data is not initialized: $apptainer_data_dir" >&2
  exit 1
}
if [[ -e $smoke_host_dir || -L $smoke_host_dir ]]; then
  echo "$smoke_host_dir already exists" >&2
  exit 1
fi
if [[ ! -d $work_dir ]]; then
  mkdir -p -- "$work_dir"
  created_work_dir=1
fi
cleanup_smoke_dir=1

started_at=$(date +%s)
if timeout --foreground --signal=TERM --kill-after=10s 180s \
  apptainer exec \
  --cleanenv \
  --no-home \
  --net --network none \
  --bind "$work_dir:/work" \
  --bind "$apptainer_data_dir:/data" \
  "$apptainer_image" \
  env "SMOKE_EVENTS=$smoke_events" SMOKE_RUNTIME=apptainer bash -s \
  <"$script_dir/smoke-test.sh"; then
  :
else
  runtime_status=$?
  if ((runtime_status == 124)); then
    printf '[smoke] TIMEOUT (status 124)\n' >&2
  fi
  exit "$runtime_status"
fi
elapsed=$(($(date +%s) - started_at))

if [[ ! -d $smoke_host_dir ]]; then
  echo "Smoke output not found: $smoke_host_dir" >&2
  exit 1
fi
unexpected_owner=$(find "$smoke_host_dir" ! -uid "$(id -u)" -print -quit)
if [[ -n $unexpected_owner ]]; then
  echo "Smoke output has an unexpected owner: $unexpected_owner" >&2
  exit 1
fi
printf '[smoke] Apptainer smoke test time: %ss\n' "$elapsed"
if [[ $keep_work == 1 ]]; then
  printf '[smoke] Retained output: %s\n' "$smoke_host_dir"
fi
