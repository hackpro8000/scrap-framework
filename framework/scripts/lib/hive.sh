#!/usr/bin/env bash
# Sourced by the hive's scripts after lib/game.sh.
#
#   game_repository          the game's GitHub repository, owner/name
#   with_ticks <log> <cmd…>  runs a command, adding a line to <log> every minute
#
# game_repository is game.toml's repository, unless it is missing or still
# the template's placeholder; then GITHUB_REPOSITORY (set on GitHub's
# machines), else the checkout's origin remote. The same rule as
# framework/hive/game_settings.py repository().

game_repository() {
	local value url
	value="$(game_setting repository "")"
	if [ -n "${value}" ] && [ "${value}" != "owner/my-game" ]; then
		echo "${value}"
		return 0
	fi
	if [ -n "${GITHUB_REPOSITORY:-}" ]; then
		echo "${GITHUB_REPOSITORY}"
		return 0
	fi
	# https://github.com/owner/name(.git) or git@github.com:owner/name(.git)
	url="$(git -C "${GAME_ROOT}" remote get-url origin 2> /dev/null || true)"
	url="${url%/}"
	url="${url%.git}"
	if [[ "${url}" =~ [:/]([^/:]+/[^/]+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	echo "no repository: set game.toml's repository (${GAME_ROOT}/game.toml) or give the checkout an origin remote" >&2
	return 1
}

# A step that prints nothing for minutes (a cold engine compile, or waiting
# for machine 1's) would look wedged to the hub, which re-deals a unit whose
# log is quiet for 5 minutes; a line a minute shows it is still going.
with_ticks() {
	local log="$1" what ticker status=0
	shift
	what="$(basename "$1") ${*:2}"
	(
		minutes=0
		while sleep 60; do
			minutes=$((minutes + 1))
			echo "still going after ${minutes} min: ${what}"
		done
	) >> "${log}" 2>&1 &
	ticker=$!
	"$@" || status=$?
	kill "${ticker}" 2> /dev/null
	wait "${ticker}" 2> /dev/null
	return "${status}"
}
