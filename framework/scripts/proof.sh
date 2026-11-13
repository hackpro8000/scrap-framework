#!/usr/bin/env bash
# Proves the engine still builds the proof models exactly as before: each
# model is built cold and every file it writes is hashed and compared with
# the recorded baseline. Run it on a build machine, never on the user's
# computer.
#
#   framework/scripts/proof.sh            # compare with <game>/baseline.txt; exit 1 on any difference
#   framework/scripts/proof.sh --record   # print a fresh baseline to stdout
#
# The game is GAME_ROOT, or else the proof game beside the framework
# (proof/scrap-heist). The model list is <game>/models.txt, one name per line.

set -uo pipefail

GAME_ROOT="${GAME_ROOT:-$(dirname "$0")/../../proof/scrap-heist}"
source "$(dirname "$0")/lib/game.sh"
root="${GAME_ROOT}"
cd "${root}"
record=false
[ "${1:-}" = "--record" ] && record=true
baseline="${root}/baseline.txt"
models="${root}/models.txt"
differences="${root}/differences.txt"
fresh="$(mktemp)"

mkdir -p "${GAME_ROOT}/engine/bin"
"${FRAMEWORK}/scripts/build-model.sh" --engine >&2 || { echo "proof: the engine did not compile FAILED"; exit 1; }

status=0
while read -r name; do
	[ -n "${name}" ] || continue
	dir="art/models/${name}"
	started=${SECONDS}
	rm -rf "${dir}"
	mkdir -p "${dir}"
	"${FRAMEWORK}/scripts/assemble-model.sh" "${name}" >&2 || { echo "proof ${name} did not assemble FAILED"; status=1; continue; }
	MODELKIT_NO_CACHE=1 "${FRAMEWORK}/scripts/build-model.sh" "${name}" -- --turntable 2 > "${dir}/proof.out" 2> "${dir}/proof.err" ||
		{ echo "proof ${name} did not build FAILED"; tail -n 5 "${dir}/proof.err" >&2; status=1; continue; }
	# Logs and timings change from run to run; everything else must not.
	(cd "${dir}" && find . -type f ! -path './.cache/*' ! -name '*.out' ! -name '*.err' ! -name '*.log' ! -name '*.txt' |
		LC_ALL=C sort | while read -r file; do
			echo "${name} ${file#./} $(sha256sum "${file}" | cut -c1-64)"
		done) >> "${fresh}"
	echo "proof ${name} built in $((SECONDS - started))s" >&2
done < "${models}"

if ${record}; then
	cat "${fresh}"
	exit "${status}"
fi
[ "${status}" -eq 0 ] || exit 1
if diff <(LC_ALL=C sort "${baseline}") <(LC_ALL=C sort "${fresh}") > "${differences}"; then
	echo "PROOF OK: $(wc -l < "${fresh}") files identical across $(wc -l < "${models}") models"
else
	echo "PROOF DIFFERENT: $(rg -c '^[<>]' "${differences}") lines differ"
	cut -c1-120 "${differences}" | head -n 40
	exit 1
fi
