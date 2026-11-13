#!/usr/bin/env bash
# Sourced by every framework script. Sets where things are and reads the
# game's settings, so no script has a game's name or paths written into it.
#
#   FRAMEWORK   the framework folder (this copy; never edited inside a game)
#   GAME_ROOT   the game the script works on: the folder holding game.toml.
#               Defaults to the folder that contains framework/; set it to
#               work on another game (the proof uses proof/scrap-heist).
#   game_setting <key> [default]   one value from ${GAME_ROOT}/game.toml
#
# game.toml is flat: one `key = "value"` or `key = number` per line.

FRAMEWORK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME_ROOT="$(cd "${GAME_ROOT:-${FRAMEWORK}/..}" && pwd)"
export FRAMEWORK GAME_ROOT

game_setting() {
	local key="$1" value
	value="$(awk -v key="${key}" -F ' *= *' '$1 == key { sub(/^[^=]*= */, ""); gsub(/^"|"$/, ""); print; exit }' "${GAME_ROOT}/game.toml" 2> /dev/null)"
	if [ -n "${value}" ]; then
		echo "${value}"
	elif [ $# -ge 2 ]; then
		echo "$2"
	else
		echo "game.toml has no setting '${key}' (${GAME_ROOT}/game.toml)" >&2
		return 1
	fi
}

# Per-user folders for this game's caches and keys.
game_cache_dir() { echo "${HOME}/.cache/$(game_setting name)"; }
game_config_dir() { echo "${HOME}/.config/$(game_setting name)"; }
