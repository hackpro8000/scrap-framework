#!/usr/bin/env bash
# Replaces this game's framework/ with a release of the framework.
#
#   framework-update.sh <version> [--from <git url or local path>] [--force]
#
# The source is --from, else game.toml's framework_source. Fetches the tag
# framework-v<version> into a temporary folder outside the game, refuses a
# release whose files do not match its own manifest, and refuses when this
# game's framework/ has local changes (unless --force, which loses them).
# Keeps the build folders engine/target, engine/bin and uikit/target.
# Never commits.
set -euo pipefail
source "$(dirname "$0")/lib/game.sh"

WORK=""
trap '[ -z "${WORK}" ] || rm -rf "${WORK}"' EXIT

fail() {
	echo "framework-update: $*" >&2
	exit 1
}

# Deletes every file in framework/ except the build folders, then copies the release in.
replace_framework() {
	local fetched="$1"
	[ "$(basename "${FRAMEWORK}")" = "framework" ] || fail "refusing to replace ${FRAMEWORK}: not a framework/ folder"
	(
		cd "${FRAMEWORK}"
		find . \( -path ./engine/target -o -path ./engine/bin -o -path ./uikit/target \) -prune \
			-o \( -type f -o -type l \) -print0 | xargs -0 -r rm -f
		find . -mindepth 1 -type d -empty -delete
	)
	cp -a "${fetched}/." "${FRAMEWORK}/"
}

# Changelog entries newer than the version the game had.
print_changes() {
	local changelog="$1" old="$2"
	echo "Changes since ${old}:"
	awk -v old="${old}" '/^## / { if ($2 == old) exit; show = 1 } show { print "\t" $0 }' "${changelog}"
}

main() {
	local version="" source="" force=0
	while [ $# -gt 0 ]; do
		case "$1" in
			--from) source="${2:-}"; shift 2 || fail "--from needs a git url or path" ;;
			--force) force=1; shift ;;
			-*) fail "unknown option $1" ;;
			*) version="$1"; shift ;;
		esac
	done
	[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
		fail "usage: framework-update.sh <version> [--from <git url or local path>] [--force]"
	[ -n "${source}" ] || source="$(game_setting framework_source "")"
	[ -n "${source}" ] ||
		fail "no source: add framework_source = \"<git url of the framework repository>\" to ${GAME_ROOT}/game.toml, or pass --from"

	WORK="$(mktemp -d "${TMPDIR:-/tmp}/framework-update.XXXXXX")"
	case "${WORK}/" in
		"${GAME_ROOT}"/*) fail "the temporary folder ${WORK} is inside the game; set TMPDIR elsewhere" ;;
	esac
	local url="${source}"
	[ -d "${source}" ] && url="file://$(cd "${source}" && pwd)"
	local tag="framework-v${version}"
	git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${tag}" -- "${url}" "${WORK}/release" ||
		fail "could not fetch tag ${tag} from ${source}"

	local fetched="${WORK}/release/framework"
	[ -f "${fetched}/scripts/framework-check.sh" ] || fail "${tag} has no framework/scripts/framework-check.sh"
	if ! GAME_ROOT="${WORK}/release" bash "${fetched}/scripts/framework-check.sh" > "${WORK}/release-check.txt" 2>&1; then
		cat "${WORK}/release-check.txt" >&2
		fail "release ${tag} does not match its own manifest (above); not installing it"
	fi
	local fetched_version
	fetched_version="$(cat "${fetched}/VERSION")"
	[ "${fetched_version}" = "${version}" ] || fail "${tag} says it is version ${fetched_version}"

	if ! "${FRAMEWORK}/scripts/framework-check.sh" > "${WORK}/game-check.txt" 2>&1; then
		cat "${WORK}/game-check.txt" >&2
		[ "${force}" -eq 1 ] ||
			fail "this game's framework/ has local changes (above) that the update would lose. Make them in the framework repository, or rerun with --force to drop them."
		echo "--force: replacing framework/ anyway; the differences above are lost." >&2
	fi

	local old
	old="$(cat "${FRAMEWORK}/VERSION" 2> /dev/null || echo none)"
	replace_framework "${fetched}"
	echo "framework/ replaced: ${old} -> ${version} (from ${source})"
	print_changes "${FRAMEWORK}/CHANGELOG.md" "${old}"
	"${FRAMEWORK}/scripts/framework-check.sh"
	cat << EOF

Next (nothing is committed):
	git diff --stat framework/    review what changed
	run the engine proof and the game's tests (the engine compiles on the build machines)
	git add -A framework && git commit    once they pass
EOF
}

main "$@"
exit $?
