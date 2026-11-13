#!/usr/bin/env bash
# Paints one UI kit, or every kit, from its art/ui/<Kit>/ui.luau with the
# prebuilt uikit engine in framework/uikit/bin. When Rust is installed it
# rebuilds the engine first and refreshes that binary, which then needs
# committing along with the engine change.
#
#   framework/scripts/build-ui.sh <Kit>
#   framework/scripts/build-ui.sh           # all kits

set -euo pipefail

source "$(dirname "$0")/lib/game.sh"
root="${GAME_ROOT}"
uikit="${FRAMEWORK}/uikit/bin/uikit-linux-x64"
if command -v cargo >/dev/null 2>&1; then
	cargo build -q --release --manifest-path "${FRAMEWORK}/uikit/Cargo.toml"
	built="${FRAMEWORK}/uikit/target/release/uikit"
	cmp -s "${built}" "${uikit}" || cp "${built}" "${uikit}"
fi

kits=("$@")
if [ ${#kits[@]} -eq 0 ]; then
	for dir in "${root}"/art/ui/*/; do
		kits+=("$(basename "${dir}")")
	done
fi

for name in "${kits[@]}"; do
	dir="${root}/art/ui/${name}"
	if [ ! -f "${dir}/ui.luau" ]; then
		echo "no kit script: ${dir}/ui.luau" >&2
		exit 1
	fi
	"${uikit}" "${dir}"
	# The game reads each element's size and slice from a copy in src, since
	# Rojo only syncs src.
	mkdir -p "${root}/src/shared/UI"
	cp "${dir}/slices.luau" "${root}/src/shared/UI/${name}Slices.luau"
done
