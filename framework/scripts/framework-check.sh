#!/usr/bin/env bash
# Checks that framework/ is exactly the release it claims to be: every file in
# framework/MANIFEST has its recorded hash, and no other file is present.
# Framework files are changed in the framework repository, never in a game,
# and arrive through framework/scripts/framework-update.sh.
#
#   framework-check.sh           prints FRAMEWORK OK <version>, or the differences (exit 1)
#   framework-check.sh --files   lists the files a release covers (framework-release.sh uses it)
#
# Works with or without git: in a git repository it looks at tracked files and
# untracked ones that are not ignored; elsewhere at every file on disk.
set -euo pipefail
source "$(dirname "$0")/lib/game.sh"

# Build outputs and caches inside framework/ that no release contains.
is_build_output() {
	case "$1" in
		MANIFEST | engine/target/* | engine/bin/* | uikit/target/* | __pycache__/* | */__pycache__/*) return 0 ;;
	esac
	return 1
}

# Every file under framework/, relative to it, one per line, sorted.
framework_files() {
	(
		cd "${FRAMEWORK}"
		if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
			git ls-files -z --cached --others --exclude-standard
		else
			find . \( -path ./engine/target -o -path ./engine/bin -o -path ./uikit/target -o -name __pycache__ \) -prune \
				-o \( -type f -o -type l \) -print0
		fi | while IFS= read -r -d '' path; do
			path="${path#./}"
			is_build_output "${path}" && continue
			# Deleted but still tracked: not present, so not extra.
			[ -e "${path}" ] || [ -L "${path}" ] || continue
			echo "${path}"
		done | LC_ALL=C sort -u
	)
}

# Manifest files whose hash differs or that are gone.
hash_problems() {
	(cd "${FRAMEWORK}" && sha256sum -c --quiet MANIFEST 2> /dev/null || true) | awk '
		sub(/: FAILED open or read$/, "") { print "missing: " $0; next }
		sub(/: FAILED$/, "") { print "changed: " $0 }
	'
}

# Files present that the manifest does not list.
extra_files() {
	LC_ALL=C comm -13 \
		<(awk '{ sub(/^[0-9a-f]+ [ *]/, ""); print }' "${FRAMEWORK}/MANIFEST" | LC_ALL=C sort -u) \
		<(framework_files) | awk '{ print "extra: " $0 }'
}

explain() {
	echo "Framework files are changed in the framework repository and arrive through framework/scripts/framework-update.sh; a game never edits them." >&2
}

main() {
	if [ "${1:-}" = "--files" ]; then
		framework_files
		return 0
	fi
	if [ ! -f "${FRAMEWORK}/MANIFEST" ]; then
		echo "framework/MANIFEST is missing, so framework/ is not a release." >&2
		explain
		return 1
	fi
	local version problems
	version="$(cat "${FRAMEWORK}/VERSION" 2> /dev/null || echo unknown)"
	problems="$(hash_problems; extra_files)"
	if [ -z "${problems}" ]; then
		echo "FRAMEWORK OK ${version}"
		return 0
	fi
	echo "${problems}"
	echo "framework/ differs from release ${version}." >&2
	explain
	return 1
}

main "$@"
