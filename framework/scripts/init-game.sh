#!/usr/bin/env bash
# Turns a fresh copy of the template into a new game. Run once.
#
#   init-game.sh <name> "<Display Name>" <owner/repository> [--force]
#
# Rewrites game.toml (name, display_name, repository, host_prefix; keeps
# framework_source and every other key), default.project.json's name and
# wally.toml's package name, and removes proof/. Refuses when game.toml's name
# is no longer the template's my-game, unless --force.
set -euo pipefail
source "$(dirname "$0")/lib/game.sh"

fail() {
	echo "init-game: $*" >&2
	exit 1
}

# Sets flat game.toml keys from SET_<key> environment values; appends missing ones.
set_settings() {
	local toml="$1" written
	written="$(awk -v keys="name display_name repository host_prefix" '
		BEGIN { split(keys, list, " "); for (i in list) wanted[list[i]] = 1 }
		($1 in wanted) && $2 == "=" { print $1 " = \"" ENVIRON["SET_" $1] "\""; seen[$1] = 1; next }
		{ print }
		END { for (i = 1; i in list; i++) if (!(list[i] in seen)) print list[i] " = \"" ENVIRON["SET_" list[i]] "\"" }
	' "${toml}")"
	printf '%s\n' "${written}" > "${toml}"
}

rename_project_json() {
	local file="$1" name="$2" written
	if command -v jq > /dev/null; then
		written="$(jq --tab --arg name "${name}" '.name = $name' "${file}")"
		printf '%s\n' "${written}" > "${file}"
	else
		sd -n 1 '"name": "[^"]*"' "\"name\": \"${name}\"" "${file}"
	fi
}

# Wally names are scope/name: keeps the scope, sets the name.
rename_wally_package() {
	local file="$1" name="$2" written
	written="$(NAME="${name}" awk '
		/^\[/ { in_package = ($0 == "[package]") }
		in_package && $1 == "name" && $2 == "=" { sub(/\/[^"]*"/, "/" ENVIRON["NAME"] "\"") }
		{ print }
	' "${file}")"
	printf '%s\n' "${written}" > "${file}"
}

main() {
	local force=0 args=()
	for arg in "$@"; do
		if [ "${arg}" = "--force" ]; then force=1; else args+=("${arg}"); fi
	done
	[ ${#args[@]} -eq 3 ] || fail "usage: init-game.sh <name> \"<Display Name>\" <owner/repository> [--force]"
	local name="${args[0]}" display="${args[1]}" repository="${args[2]}"
	[[ "${name}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail "name must be lowercase letters, digits and dashes, got '${name}'"
	[ -n "${display}" ] || fail "the display name is empty"
	[[ "${display}" != *[\"\\]* ]] || fail "the display name cannot hold quotes or backslashes"
	[[ "${repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "repository must look like owner/repository, got '${repository}'"

	local toml="${GAME_ROOT}/game.toml"
	[ -f "${toml}" ] || fail "no game.toml in ${GAME_ROOT}"
	local current
	current="$(game_setting name "")"
	[ "${current}" = "my-game" ] || [ "${force}" -eq 1 ] ||
		fail "game.toml's name is '${current}', not the template's my-game: this game is already set up. Use --force to rename it anyway."
	local source
	source="$(game_setting framework_source "")"
	[ -n "${source}" ] ||
		fail "game.toml has no framework_source; add framework_source = \"<git url of the framework repository>\" first"

	SET_name="${name}" SET_display_name="${display}" SET_repository="${repository}" SET_host_prefix="${name//-/}" \
		set_settings "${toml}"
	echo "game.toml: name = ${name}, display_name = ${display}, repository = ${repository}, host_prefix = ${name//-/}"
	echo "game.toml: framework_source kept as ${source}"
	if [ -f "${GAME_ROOT}/default.project.json" ]; then
		rename_project_json "${GAME_ROOT}/default.project.json" "${name}"
		echo "default.project.json: name = ${name}"
	fi
	if [ -f "${GAME_ROOT}/wally.toml" ]; then
		rename_wally_package "${GAME_ROOT}/wally.toml" "${name}"
		echo "wally.toml: package name ends in /${name} (check the scope before it)"
	fi
	if [ -d "${GAME_ROOT}/proof" ]; then
		rm -rf "${GAME_ROOT:?}/proof"
		echo "proof/: removed (it belongs to the framework repository)"
	fi
	# Files that only the framework repository needs: its own design notes
	# and the workflow that runs the proof game.
	local extra
	for extra in docs/plans/template-framework.md .github/workflows/proof.yml; do
		[ -e "${GAME_ROOT}/${extra}" ] || continue
		rm -f "${GAME_ROOT:?}/${extra}"
		echo "${extra}: removed (it belongs to the framework repository)"
	done
	if [ -f "${GAME_ROOT}/.gitignore" ] && rg -q '^proof/' "${GAME_ROOT}/.gitignore"; then
		rg -v '^proof/' "${GAME_ROOT}/.gitignore" > "${GAME_ROOT}/.gitignore.new" || true
		mv "${GAME_ROOT}/.gitignore.new" "${GAME_ROOT}/.gitignore"
		echo ".gitignore: proof lines removed"
	fi
	cat << EOF

Next:
	review game.toml and set the other keys (default_layout, cloud_environment, sample_models, ...)
	framework/scripts/framework-check.sh    should print FRAMEWORK OK
	git add -A && git commit                 the start of ${display}
	framework/scripts/framework-update.sh <version>    later, to take a newer framework
EOF
}

main "$@"
