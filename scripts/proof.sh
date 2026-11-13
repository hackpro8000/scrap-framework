#!/usr/bin/env bash
# Proves the engine still builds the proof models exactly as before: each
# model is built cold and every file it writes is hashed and compared with
# the recorded baseline. Run it on a build machine, never on the user's
# computer.
#
#   scripts/proof.sh            # compare with proof/baseline.txt; exit 1 on any difference
#   scripts/proof.sh --record   # print a fresh baseline to stdout
#
# The model list is proof/models.txt, one name per line.

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
record=false
[ "${1:-}" = "--record" ] && record=true
baseline="proof/baseline.txt"
fresh="$(mktemp)"

mkdir -p tools/modelkit/bin
scripts/build-model.sh --engine >&2 || { echo "proof: the engine did not compile FAILED"; exit 1; }

status=0
while read -r name; do
	[ -n "${name}" ] || continue
	dir="art/models/${name}"
	started=${SECONDS}
	rm -rf "${dir}"
	mkdir -p "${dir}"
	scripts/assemble-model.sh "${name}" >&2 || { echo "proof ${name} did not assemble FAILED"; status=1; continue; }
	MODELKIT_NO_CACHE=1 scripts/build-model.sh "${name}" -- --turntable 2 > "${dir}/proof.out" 2> "${dir}/proof.err" ||
		{ echo "proof ${name} did not build FAILED"; tail -n 5 "${dir}/proof.err" >&2; status=1; continue; }
	# Logs and timings change from run to run; everything else must not.
	(cd "${dir}" && find . -type f ! -path './.cache/*' ! -name '*.out' ! -name '*.err' ! -name '*.log' ! -name '*.txt' |
		LC_ALL=C sort | while read -r file; do
			echo "${name} ${file#./} $(sha256sum "${file}" | cut -c1-64)"
		done) >> "${fresh}"
	echo "proof ${name} built in $((SECONDS - started))s" >&2
done < proof/models.txt

if ${record}; then
	cat "${fresh}"
	exit "${status}"
fi
[ "${status}" -eq 0 ] || exit 1
if diff <(LC_ALL=C sort "${baseline}") <(LC_ALL=C sort "${fresh}") > proof/differences.txt; then
	echo "PROOF OK: $(wc -l < "${fresh}") files identical across $(wc -l < proof/models.txt) models"
else
	echo "PROOF DIFFERENT: $(rg -c '^[<>]' proof/differences.txt) lines differ"
	cut -c1-120 proof/differences.txt | head -n 40
	exit 1
fi
