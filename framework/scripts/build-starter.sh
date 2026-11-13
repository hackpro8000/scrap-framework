#!/usr/bin/env bash
# Builds the game's models cold, each with a two-frame turntable, so a new
# game sees its kit and models work. Run it on a build machine, never on the
# user's computer (the starter workflow does).
#
#   framework/scripts/build-starter.sh
#
# The models are those named in <game>/models.txt, one per line, or else
# every art/src/items/*.luau. Exits 1 if any model fails.

set -uo pipefail

source "$(dirname "$0")/lib/game.sh"
cd "${GAME_ROOT}"

models=()
if [ -f models.txt ]; then
	mapfile -t models < <(awk 'NF && $1 !~ /^#/ { print $1 }' models.txt)
else
	for file in art/src/items/*.luau; do
		[ -f "${file}" ] && models+=("$(basename "${file}" .luau)")
	done
fi
[ "${#models[@]}" -gt 0 ] || { echo "starter: no models in models.txt or art/src/items FAILED"; exit 1; }

mkdir -p "${FRAMEWORK}/engine/bin"
"${FRAMEWORK}/scripts/build-model.sh" --engine >&2 || { echo "starter: the engine did not compile FAILED"; exit 1; }

status=0
for name in "${models[@]}"; do
	dir="art/models/${name}"
	started=${SECONDS}
	rm -rf "${dir}"
	mkdir -p "${dir}"
	if ! "${FRAMEWORK}/scripts/assemble-model.sh" "${name}" 2> "${dir}/starter.err" ||
		! MODELKIT_NO_CACHE=1 "${FRAMEWORK}/scripts/build-model.sh" "${name}" -- --turntable 2 > "${dir}/starter.out" 2>> "${dir}/starter.err"; then
		echo "starter ${name} FAILED"
		tail -n 8 "${dir}/starter.err"
		status=1
		continue
	fi
	echo "starter ${name} built in $((SECONDS - started))s"
done
exit "${status}"
