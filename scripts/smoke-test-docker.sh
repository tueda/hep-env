#!/usr/bin/env bash

# Run the end-to-end smoke test in a disposable Docker container.
#
# Usage:
#   ./scripts/smoke-test-docker.sh
#   SMOKE_EVENTS=200 ./scripts/smoke-test-docker.sh
#   DOCKER_IMAGE=example/image@sha256:... ./scripts/smoke-test-docker.sh
#
# Environment:
#   DOCKER_IMAGE  Image reference to test (default: hep-env-local).
#   SMOKE_EVENTS  Number of generated events (default: 1000).
#
# The container has no host bind mounts. Its /work and /data changes disappear
# when Docker removes the container.

set -euo pipefail

usage() {
  sed -n '3,15s/^# \{0,1\}//p' "$0"
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
docker_image=${DOCKER_IMAGE:-hep-env-local}
smoke_events=${SMOKE_EVENTS:-1000}

if [[ ! $smoke_events =~ ^[1-9][0-9]*$ ]]; then
  echo "SMOKE_EVENTS must be a positive integer: $smoke_events" >&2
  exit 2
fi
command -v docker >/dev/null
command -v timeout >/dev/null

started_at=$(date +%s)
if timeout --foreground --signal=TERM --kill-after=10s 180s \
  docker run --rm -i --network none \
  --env "SMOKE_EVENTS=$smoke_events" \
  --env SMOKE_RUNTIME=docker \
  "$docker_image" bash -s <"$script_dir/smoke-test.sh"; then
  :
else
  runtime_status=$?
  if ((runtime_status == 124)); then
    printf '[smoke] TIMEOUT (status 124)\n' >&2
  fi
  exit "$runtime_status"
fi
elapsed=$(($(date +%s) - started_at))
printf '[smoke] Docker smoke test time: %ss\n' "$elapsed"
