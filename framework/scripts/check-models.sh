#!/usr/bin/env bash
# Checks models for floating pieces and broken surfaces
# (framework/modelcheck/check.luau), only those whose assembled script changed
# since they were last checked. Run before a layout build;
# framework/scripts/send-build.sh does.
#
#   framework/scripts/check-models.sh                 # every model the game's default layout uses
#   framework/scripts/check-models.sh <Name>...       # just these
#   CHECK_ALL=1 framework/scripts/check-models.sh     # recheck even unchanged ones
#
# Each model's last result is kept beside it, in
# art/models/<Name>/check.txt (the script's hash, then ok or the problems),
# so an unchanged model is never checked twice. Exits 1 when a model that
# changed has a problem; one that hasn't changed since it last failed
# doesn't stop the build, so old models can be fixed in their own time.

set -uo pipefail

source "$(dirname "$0")/lib/game.sh"
root="${GAME_ROOT}"
cd "${root}"
if [ $# -eq 0 ]; then
	set -- $(head -n 1 "art/src/layouts/$(game_setting default_layout).luau" | sed 's/^-- uses://')
fi

changed=()
for name in "$@"; do
	script="art/models/${name}/model.luau"
	[ -f "${script}" ] || continue
	hash="$(sha1sum "${script}" | cut -c1-16)"
	last="art/models/${name}/check.txt"
	if [ -z "${CHECK_ALL:-}" ] && [ -f "${last}" ] && [ "$(head -n 1 "${last}")" = "${hash}" ]; then
		continue
	fi
	changed+=("${name}")
done
if [ ${#changed[@]} -eq 0 ]; then
	echo "check-models: nothing changed since the last check" >&2
	exit 0
fi

failed=0
while IFS= read -r line; do
	echo "${line}"
	name="$(awk '{ print $2 }' <<< "${line}")"
	[ -d "art/models/${name}" ] || continue
	{ sha1sum "art/models/${name}/model.luau" | cut -c1-16; echo "${line}"; } > "art/models/${name}/check.txt"
	case "${line}" in FAIL*) failed=1 ;; esac
done < <(lune run "${FRAMEWORK}/modelcheck/check" "${changed[@]}")
exit "${failed}"
