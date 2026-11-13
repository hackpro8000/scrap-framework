#!/usr/bin/env bash
# Compiles the engine on a GitHub machine (never on this computer) and prints
# the compiler's errors and warnings. The working tree is pushed as a snapshot
# first, as framework/scripts/push-wip.sh does.
#
#   framework/scripts/engine-check.sh           # cargo check, errors only matter
#   framework/scripts/engine-check.sh --share   # release build, shared on build-engine

set -euo pipefail

source "$(dirname "$0")/lib/game.sh"
cd "${GAME_ROOT}"
share=false
[ "${1:-}" = "--share" ] && share=true
branch="wip/engine-check"
workflow_ref="${ENGINE_CHECK_WORKFLOW_REF:-${branch}}"

"${FRAMEWORK}/scripts/push-wip.sh" "${branch}" > /dev/null
before="$(gh run list --workflow engine-check.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
# The game's folder from the repository root: its engine is the one compiled.
game="$(realpath --relative-to="$(git rev-parse --show-toplevel)" "${GAME_ROOT}")"
gh workflow run engine-check.yml --ref "${workflow_ref}" -f ref="${branch}" -f share="${share}" -f game="${game}"
run="${before}"
for _ in $(seq 30); do
	sleep 2
	run="$(gh run list --workflow engine-check.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
	[ "${run}" != "${before}" ] && break
done
[ "${run}" != "${before}" ] || { echo "the engine-check run did not start" >&2; exit 1; }
echo "engine-check run ${run}" >&2
status=0
gh run watch "${run}" --exit-status > /dev/null 2>&1 || status=$?
gh run view "${run}" --log 2> /dev/null | rg -e 'error(\[|:)|warning:|-->|Finished|could not compile' | cut -f3- | cut -c1-240 || true
[ "${status}" -eq 0 ] && echo "ENGINE OK" || echo "ENGINE FAILED"
exit "${status}"
