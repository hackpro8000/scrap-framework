#!/usr/bin/env bash
# Posts a map build for Claude cloud machines that need no prompt: one
# branch per shard, cloud-task/<task>/s<i>, each a commit on top of the
# build's commit whose message names its shard. A session created in the
# game's cloud environment (cloud_environment in game.toml) on that branch builds the shard as it starts
# (framework/scripts/cloud-task.sh) and pushes cloud-results/<task>/s<i>;
# framework/scripts/cloud-results.sh collects them.
#
#   framework/scripts/cloud-dispatch.sh <task> <count> [commit, default: the working
#                                             tree, pushed with push-wip.sh]
#                             [layout, default: the game's default_layout]
set -euo pipefail

source "$(dirname "$0")/lib/game.sh"
task="${1:?task name required}"
count="${2:?shard count required}"
cd "${GAME_ROOT}"
commit="${3:-$("${FRAMEWORK}/scripts/push-wip.sh" wip/cloud-task)}"
layout="${4:-$(game_setting default_layout)}"
commit="$(git rev-parse --verify "${commit}^{commit}")"
tree="$(git rev-parse "${commit}^{tree}")"

refs=()
for index in $(seq 1 "${count}"); do
	shard="$(git commit-tree "${tree}" -p "${commit}" -m "cloud-task ${task} shard ${index} of ${count} ${layout}")"
	refs+=("${shard}:refs/heads/cloud-task/${task}/s${index}")
done
git push -q -f origin "${refs[@]}"
echo "posted ${task}: ${count} branches cloud-task/${task}/s1..s${count} on ${commit:0:8}" >&2
