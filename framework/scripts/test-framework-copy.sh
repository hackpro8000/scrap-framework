#!/usr/bin/env bash
# End-to-end test of the pinned framework copy: release, init-game, check and
# update, all inside a temporary folder. Only reads this repository (it copies
# the four framework scripts and lib/game.sh). Prints PASS/FAIL per case.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
unset GAME_ROOT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
T="$(mktemp -d "${TMPDIR:-/tmp}/framework-copy-test.XXXXXX")"
trap 'rm -rf "${T}"' EXIT
FW="${T}/framework-repo"
G="${T}/game"
failures=0
rc=0

expect() {
	local name="$1" condition="$2"
	if eval "${condition}"; then
		echo "PASS ${name}"
	else
		echo "FAIL ${name}"
		failures=$((failures + 1))
	fi
}

fw_git() { git -C "${FW}" "$@" > /dev/null; }
game_git() { git -C "${G}" "$@" > /dev/null; }
has() { rg -q --fixed-strings -- "$2" "$1"; }

make_framework_repo() {
	mkdir -p "${FW}/framework/scripts/lib" "${FW}/framework/engine/src" "${FW}/framework/docs" "${FW}/proof/sample"
	cp "${HERE}"/{framework-check,framework-update,framework-release,init-game}.sh "${FW}/framework/scripts/"
	cp "${HERE}/lib/game.sh" "${FW}/framework/scripts/lib/"
	printf '# Framework changelog\n\nNewest first.\n\n' > "${FW}/framework/CHANGELOG.md"
	echo "0.0.0" > "${FW}/framework/VERSION"
	echo "fn main() {}" > "${FW}/framework/engine/src/main.rs"
	echo "old" > "${FW}/framework/engine/src/remove-me.rs"
	echo "# notes" > "${FW}/framework/docs/notes.md"
	printf 'name = "my-game"\ndisplay_name = "My Game"\nrepository = "owner/my-game"\nhost_prefix = "mygame"\n# Where framework-update.sh fetches releases.\nframework_source = "%s"\ntexture_cap = 1024\n' "${FW}" > "${FW}/game.toml"
	printf '{\n\t"name": "my-game",\n\t"tree": {}\n}\n' > "${FW}/default.project.json"
	printf '[package]\nname = "my-studio/my-game"\nversion = "0.1.0"\n' > "${FW}/wally.toml"
	printf 'framework/engine/target/\nframework/engine/bin/\nframework/uikit/target/\n' > "${FW}/.gitignore"
	echo 'name = "sample"' > "${FW}/proof/sample/game.toml"
	git init -q -b main "${FW}"
	fw_git add -A
	fw_git commit -qm start
}

release() {
	bash "${FW}/framework/scripts/framework-release.sh" "$@" > "${T}/release.txt" 2>&1
	rc=$?
}

publish() {
	fw_git add -A
	fw_git commit -qm "framework $1"
	fw_git tag "framework-v$1"
}

make_framework_repo
release 0.1.0 safe "First release"
expect release-prepares $'[ ${rc} -eq 0 ] && [ "$(cat "${FW}/framework/VERSION")" = 0.1.0 ] && has "${FW}/framework/MANIFEST" "  engine/src/main.rs" && has "${FW}/framework/CHANGELOG.md" "## 0.1.0 (safe)"'
expect release-never-commits '[ "$(git -C "${FW}" rev-list --count HEAD)" = 1 ] && [ -z "$(git -C "${FW}" tag)" ] && has "${T}/release.txt" "git tag framework-v0.1.0"'
release 0.1.1 safe "Dirty tree"
expect release-refuses-dirty-tree '[ ${rc} -ne 0 ] && has "${T}/release.txt" "uncommitted changes"'
publish 0.1.0

cp -a "${FW}" "${G}"
rm -rf "${G}/.git"
bash "${G}/framework/scripts/init-game.sh" space-crab "Space Crab" someone/space-crab > "${T}/init.txt" 2>&1
rc=$?
expect init-game $'[ ${rc} -eq 0 ] && has "${G}/game.toml" \'name = "space-crab"\' && has "${G}/game.toml" \'host_prefix = "spacecrab"\' && has "${G}/game.toml" \'display_name = "Space Crab"\' && has "${G}/game.toml" \'repository = "someone/space-crab"\' && has "${G}/game.toml" "framework_source = \\"${FW}\\"" && has "${G}/game.toml" "texture_cap = 1024" && [ "$(jq -r .name "${G}/default.project.json")" = space-crab ] && has "${G}/wally.toml" \'name = "my-studio/space-crab"\' && [ ! -e "${G}/proof" ]'
bash "${G}/framework/scripts/init-game.sh" other "Other" someone/other > /dev/null 2>&1
rc=$?
expect init-game-refuses-second-run $'[ ${rc} -ne 0 ] && has "${G}/game.toml" \'name = "space-crab"\''

cp -a "${G}" "${T}/game-no-git"
"${T}/game-no-git/framework/scripts/framework-check.sh" > "${T}/check.txt" 2>&1
rc=$?
expect check-ok-without-git '[ ${rc} -eq 0 ] && has "${T}/check.txt" "FRAMEWORK OK 0.1.0"'
git init -q -b main "${G}"
game_git add -A
game_git commit -qm "start space-crab"
"${G}/framework/scripts/framework-check.sh" > "${T}/check.txt" 2>&1
rc=$?
expect check-ok-in-git '[ ${rc} -eq 0 ] && has "${T}/check.txt" "FRAMEWORK OK 0.1.0"'

echo "local edit" >> "${G}/framework/docs/notes.md"
touch "${G}/framework/docs/extra.md"
rm "${G}/framework/engine/src/remove-me.rs"
"${G}/framework/scripts/framework-check.sh" > "${T}/check.txt" 2>&1
rc=$?
expect check-finds-local-edits '[ ${rc} -eq 1 ] && has "${T}/check.txt" "changed: docs/notes.md" && has "${T}/check.txt" "extra: docs/extra.md" && has "${T}/check.txt" "missing: engine/src/remove-me.rs" && has "${T}/check.txt" "framework-update.sh"'
bash "${G}/framework/scripts/framework-update.sh" 0.1.0 --from "${FW}" > "${T}/update.txt" 2>&1
rc=$?
expect update-refuses-local-edits '[ ${rc} -ne 0 ] && has "${T}/update.txt" "changed: docs/notes.md" && has "${G}/framework/docs/notes.md" "local edit"'
game_git checkout -- framework
rm "${G}/framework/docs/extra.md"

mkdir -p "${T}/no-source"
echo 'name = "no-source"' > "${T}/no-source/game.toml"
GAME_ROOT="${T}/no-source" bash "${G}/framework/scripts/framework-update.sh" 0.1.0 > "${T}/update.txt" 2>&1
rc=$?
expect update-needs-a-source '[ ${rc} -ne 0 ] && has "${T}/update.txt" "framework_source"'

echo "fn main() { build(); }" > "${FW}/framework/engine/src/main.rs"
echo "new" > "${FW}/framework/engine/src/added.rs"
fw_git rm -q framework/engine/src/remove-me.rs
fw_git add -A
fw_git commit -qm "engine changes"
release 0.2.0 look-changing "Edges shade differently"
publish 0.2.0

mkdir -p "${G}/framework/engine/target"
echo "built" > "${G}/framework/engine/target/x"
commits="$(git -C "${G}" rev-list --count HEAD)"
bash "${G}/framework/scripts/framework-update.sh" 0.2.0 --from "${FW}" > "${T}/update.txt" 2>&1
rc=$?
expect update-succeeds '[ ${rc} -eq 0 ]'
expect update-replaces-files 'cmp -s "${FW}/framework/engine/src/main.rs" "${G}/framework/engine/src/main.rs" && cmp -s "${FW}/framework/engine/src/added.rs" "${G}/framework/engine/src/added.rs" && [ ! -e "${G}/framework/engine/src/remove-me.rs" ] && diff -r -x target "${FW}/framework" "${G}/framework" > /dev/null'
expect update-sets-version '[ "$(cat "${G}/framework/VERSION")" = 0.2.0 ]'
expect update-keeps-build-folder '[ "$(cat "${G}/framework/engine/target/x" 2> /dev/null)" = built ]'
expect update-prints-changelog 'has "${T}/update.txt" "## 0.2.0 (look-changing)" && has "${T}/update.txt" "Edges shade differently" && ! has "${T}/update.txt" "## 0.1.0 (safe)"'
expect update-never-commits '[ "$(git -C "${G}" rev-list --count HEAD)" = "${commits}" ] && has "${T}/update.txt" "git diff --stat framework/"'
"${G}/framework/scripts/framework-check.sh" > "${T}/check.txt" 2>&1
rc=$?
expect check-ok-after-update '[ ${rc} -eq 0 ] && has "${T}/check.txt" "FRAMEWORK OK 0.2.0"'

echo "changed after release" >> "${FW}/framework/docs/notes.md"
fw_git commit -qam "edit without a release"
fw_git tag framework-v0.3.0
bash "${G}/framework/scripts/framework-update.sh" 0.3.0 --from "${FW}" > "${T}/update.txt" 2>&1
rc=$?
expect update-refuses-broken-release '[ ${rc} -ne 0 ] && has "${T}/update.txt" "does not match its own manifest" && [ "$(cat "${G}/framework/VERSION")" = 0.2.0 ]'

[ "${failures}" -eq 0 ] || { echo "${failures} case(s) failed"; exit 1; }
echo "all cases passed"
