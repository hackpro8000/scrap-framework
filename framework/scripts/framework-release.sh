#!/usr/bin/env bash
# Prepares a framework release. Run in the framework repository only.
#
#   framework-release.sh <version> <safe|look-changing|plugin-breaking> "<summary>"
#
# Writes framework/VERSION, framework/MANIFEST (sha256 of every framework file)
# and a framework/CHANGELOG.md entry, then prints the git commands that publish
# the release. It never commits, tags or pushes by itself.
set -euo pipefail
source "$(dirname "$0")/lib/game.sh"

fail() {
	echo "framework-release: $*" >&2
	exit 1
}

usage() {
	fail "usage: framework-release.sh <version> <safe|look-changing|plugin-breaking> \"<summary>\""
}

# Puts the new entry above the newest one, below the changelog's header.
prepend_changelog_entry() {
	local changelog="$1" entry="$2" written
	written="$(ENTRY="${entry}" awk '
		!done && /^## / { print ENVIRON["ENTRY"]; print ""; done = 1 }
		{ print }
		END { if (!done) print ENVIRON["ENTRY"] }
	' "${changelog}")"
	printf '%s\n' "${written}" > "${changelog}"
}

write_manifest() {
	local manifest
	manifest="$(mktemp)"
	(
		cd "${FRAMEWORK}"
		"${FRAMEWORK}/scripts/framework-check.sh" --files | tr '\n' '\0' | xargs -0 -r sha256sum
	) > "${manifest}"
	LC_ALL=C sort -k 2 "${manifest}" > "${FRAMEWORK}/MANIFEST"
	rm -f "${manifest}"
}

main() {
	[ $# -eq 3 ] || usage
	local version="$1" kind="$2" summary="$3"
	[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3, got '${version}'"
	case "${kind}" in
		safe | look-changing | plugin-breaking) ;;
		*) usage ;;
	esac
	[ -n "${summary}" ] || fail "the summary is empty"

	git -C "${FRAMEWORK}" rev-parse --is-inside-work-tree > /dev/null 2>&1 ||
		fail "run this in the framework repository (a git checkout); ${FRAMEWORK} is not in one"
	if git -C "${FRAMEWORK}" rev-parse -q --verify "refs/tags/framework-v${version}" > /dev/null; then
		fail "tag framework-v${version} already exists"
	fi
	local dirty
	dirty="$(git -C "${FRAMEWORK}" status --porcelain -- .)"
	if [ -n "${dirty}" ]; then
		echo "${dirty}" >&2
		fail "framework/ has uncommitted changes (above); commit them first"
	fi
	local changelog="${FRAMEWORK}/CHANGELOG.md"
	[ -f "${changelog}" ] || fail "framework/CHANGELOG.md is missing"
	if awk -v v="${version}" '$1 == "##" && $2 == v { found = 1 } END { exit !found }' "${changelog}"; then
		fail "CHANGELOG.md already has an entry for ${version}"
	fi

	echo "${version}" > "${FRAMEWORK}/VERSION"
	prepend_changelog_entry "${changelog}" "$(printf '## %s (%s) - %s\n\n%s\n' "${version}" "${kind}" "$(date -u +%F)" "${summary}")"
	write_manifest
	"${FRAMEWORK}/scripts/framework-check.sh"

	local prefix
	prefix="$(git -C "${FRAMEWORK}" rev-parse --show-prefix)"
	cat << EOF

Release ${version} (${kind}) is prepared. Nothing is committed or tagged. To publish it:

	git add ${prefix}VERSION ${prefix}MANIFEST ${prefix}CHANGELOG.md
	git commit -m "framework ${version} (${kind})"
	git tag framework-v${version}
	git push origin HEAD framework-v${version}
EOF
}

main "$@"
