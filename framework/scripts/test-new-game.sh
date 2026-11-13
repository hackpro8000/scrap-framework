#!/usr/bin/env bash
# Proves a brand-new game made from this template works. Copies the committed
# tree (HEAD; uncommitted changes are not in it) into a temporary folder
# outside the checkout, makes it a git repository, runs init-game.sh there and
# checks the result. Prints PASS, FAIL or SKIP per case; exits 1 on any FAIL.
#
#   framework/scripts/test-new-game.sh           # text checks only
#   framework/scripts/test-new-game.sh --build   # also compiles the new game's engine and builds
#                                                # its example model (build machines only; the
#                                                # new-game workflow passes it)
#
# Leftover game names: lines under framework/ may match an entry in
# framework/.names-allowed; anything else naming "scrap" fails, except the
# framework_source line in game.toml (the framework repository's own address).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "${HERE}" rev-parse --show-toplevel)"
build=false
[ "${1:-}" = "--build" ] && build=true
unset GAME_ROOT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
T="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/new-game.XXXXXX")"
trap 'rm -rf "${T}"' EXIT
G="${T}/test-game"
failures=0

pass() { echo "PASS $1"; }
fail() {
	echo "FAIL $1"
	failures=$((failures + 1))
}
# Shows the end of a failed step's log.
show() { tail -n 20 "$1" | awk '{ print "    " $0 }'; }

command -v rg > /dev/null || { echo "FAIL tools: rg is needed"; exit 1; }

mkdir -p "${G}"
git -C "${REPO}" archive HEAD | tar -x -C "${G}" || { echo "FAIL copy"; exit 1; }
git -C "${G}" init -q || { echo "FAIL git-init"; exit 1; }
cd "${G}" || exit 1

if framework/scripts/init-game.sh test-game "Test Game" someone/test-game > "${T}/init.log" 2>&1; then
	pass init-game
else
	fail init-game
	show "${T}/init.log"
fi

if [ -e proof ]; then fail proof-removed; else pass proof-removed; fi

setting() { awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*= *"?/, ""); sub(/"? *$/, ""); print; exit }' game.toml; }
if [ "$(setting name)" = "test-game" ] && [ "$(setting display_name)" = "Test Game" ] && [ "$(setting repository)" = "someone/test-game" ]; then
	pass game-toml-named
else
	fail game-toml-named
	awk '$1 ~ /^(name|display_name|repository)$/' game.toml | awk '{ print "    " $0 }'
fi

# Only ^framework/ entries count: the allow-list never covers the game's own files.
allowed="framework/.names-allowed"
[ -f "${allowed}" ] || allowed="${REPO}/framework/.names-allowed"
patterns="${T}/allowed-patterns"
rg '^\^framework/' "${allowed}" > "${patterns}" 2> /dev/null || : > "${patterns}"
hits="$(rg -n -i 'scrap' --hidden -g '!.git' -g '!framework/.names-allowed' | rg -v '^game\.toml:[0-9]+:framework_source = ')"
if [ -s "${patterns}" ]; then
	left="$(printf '%s\n' "${hits}" | rg -v -f "${patterns}")"
else
	left="${hits}"
fi
if [ -z "${left}" ]; then
	pass no-old-names
else
	fail "no-old-names ($(printf '%s\n' "${left}" | wc -l) lines)"
	printf '%s\n' "${left}" | cut -c1-200 | awk '{ print "    " $0 }'
fi

if ! command -v lune > /dev/null; then
	echo "SKIP luau-tests (no lune)"
elif lune run tests/run > "${T}/lune.log" 2>&1; then
	pass luau-tests
else
	fail luau-tests
	show "${T}/lune.log"
fi

# Until the first release there is no MANIFEST, and the check says exactly that.
check_out="$(framework/scripts/framework-check.sh 2>&1)"
check_rc=$?
if [ -f framework/MANIFEST ] && [ "${check_rc}" -eq 0 ] && [[ "${check_out}" == "FRAMEWORK OK "* ]]; then
	pass framework-check
elif [ ! -f framework/MANIFEST ] && [ "${check_rc}" -eq 1 ] &&
	[[ "${check_out}" == *"framework/MANIFEST is missing, so framework/ is not a release."* ]]; then
	pass "framework-check (no MANIFEST yet: reported as missing)"
else
	fail framework-check
	printf '%s\n' "${check_out}" | head -n 10 | awk '{ print "    " $0 }'
fi

if [ "${build}" = true ]; then
	if framework/scripts/build-starter.sh > "${T}/build.log" 2>&1 && [ -f art/models/ExampleCrate/preview.png ]; then
		pass build-example
	else
		fail build-example
		show "${T}/build.log"
	fi
else
	echo "SKIP build-example (needs --build, on a build machine)"
fi

[ "${failures}" -eq 0 ] || { echo "${failures} case(s) failed"; exit 1; }
echo "all cases passed"
