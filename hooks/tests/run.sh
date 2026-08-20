#!/usr/bin/env bash
# Run every hydraia hook test. Usage: bash hooks/tests/run.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pin the artifacts base to this repo's docs/hydraia so hooks-under-test and the
# test fixtures agree, independent of any external-storage registration in the
# developer's global hydraia config. Hermetic + portable.
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
export HYDRAIA_DOCS_DIR="$REPO_ROOT/docs/hydraia"
# shellcheck source=/dev/null
. "$DIR/lib.sh"
for t in "$DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  printf '── %s\n' "$(basename "$t")"
  # shellcheck source=/dev/null
  . "$t"
done
report
