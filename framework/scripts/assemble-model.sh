#!/usr/bin/env bash
# Assembles art/models/<Name>/model.luau from the split sources in art/src:
# a bot is its head, the shared helpers, then its body; an item is the
# palette, the shared helpers, then its own file (after a CACHE_KEY); a layout is the
# placement prelude, the shared helpers, each model named on its "-- uses:" first line wrapped
# as build<Name>() and keyed by a hash of its source for modelkit's cache,
# then the layout itself.
#
# The palette and the shared helpers are the files listed in the game's
# art/style/assembly.txt ([palette] and [helpers]): the framework's mechanics
# in framework/art/lib with the game's look in art/style between them.
# An "-- include: <Name>" file comes from the game's art/src/shared, or else
# from framework/art/shared.
#
#   framework/scripts/assemble-model.sh <Name>

set -euo pipefail

name="${1:?model name required}"
source "$(dirname "$0")/lib/game.sh"
root="${GAME_ROOT}"
src="${root}/art/src"
out="${root}/art/models/${name}/model.luau"

started=${SECONDS}
# Progress goes to stderr, so the script's output stays clean.
say() {
	echo "assemble ${name}: $*" >&2
}

assembly="${root}/art/style/assembly.txt"
if [ ! -f "${assembly}" ]; then
	echo "assemble ${name}: no art/style/assembly.txt in ${root}; it lists the palette and helper files every model starts with" >&2
	exit 1
fi
palette=()
helpers=()
section=""
while IFS= read -r line; do
	case "${line}" in
		"" | "#"*) continue ;;
		"["*"]") section="${line:1:${#line}-2}"; continue ;;
		framework:*) file="${FRAMEWORK}/${line#framework:}" ;;
		style:*) file="${root}/art/style/${line#style:}" ;;
		*) echo "assemble ${name}: assembly.txt: unknown entry '${line}'" >&2; exit 1 ;;
	esac
	if [ ! -f "${file}" ]; then
		echo "assemble ${name}: assembly.txt: missing ${file}" >&2
		exit 1
	fi
	case "${section}" in
		palette) palette+=("${file}") ;;
		helpers) helpers+=("${file}") ;;
		*) echo "assemble ${name}: assembly.txt: '${line}' is outside [palette] or [helpers]" >&2; exit 1 ;;
	esac
done < "${assembly}"

# A shared file: the game's own first, then the framework's.
shared_file() {
	if [ -f "${src}/shared/$1.luau" ]; then
		echo "${src}/shared/$1.luau"
	else
		echo "${FRAMEWORK}/art/shared/$1.luau"
	fi
}

mkdir -p "$(dirname "${out}")"
if [ -d "${src}/bots/${name}" ]; then
	say "bot: head, shared helpers, body"
	cat "${src}/bots/${name}/head.luau" "${helpers[@]}" "${src}/bots/${name}/body.luau" > "${out}"
elif [ -f "${src}/items/${name}.luau" ]; then
	# CACHE_KEY hashes the shared code and the item down to "-- cached
	# above", for a model.cached build of the part above that line.
	# An "-- include: <Name>" line pulls in the shared file <Name>.luau, whose
	# own includes are pulled in too; each file comes in once, the first time.
	say "item: palette, shared helpers, item"
	item="$(awk -v shared="${src}/shared" -v kit="${FRAMEWORK}/art/shared" '
		function exists(file,    line) {
			if ((getline line < file) < 0) return 0
			close(file)
			return 1
		}
		function pull(file,    line, name, path) {
			while ((getline line < file) > 0) {
				if (line ~ /^-- include: /) {
					split(line, words, " ")
					name = words[3]
					path = shared "/" name ".luau"
					if (!exists(path)) path = kit "/" name ".luau"
					if (!(name in seen)) { seen[name] = 1; pull(path) }
				} else {
					print line
				}
			}
			close(file)
		}
		BEGIN { pull(ARGV[1]); exit }' "${src}/items/${name}.luau")"
	key="$({ cat "${palette[@]}" "${helpers[@]}"; printf '%s\n' "${item}" | sed '/^-- cached above$/q'; } | sha1sum | cut -c1-16)"
	{ echo "local CACHE_KEY = \"${name}-${key}\""; cat "${palette[@]}" "${helpers[@]}"; printf '%s\n' "${item}"; } > "${out}"
	say "cache key ${name}-${key}"
elif [ -f "${src}/layouts/${name}.luau" ]; then
	# Skipped parts never reach the cache, so the skip rule is part of each key.
	skip="$(awk '/^skipPart = function/ { open = 1 } open { print } open && /^end/ { open = 0 }' "${src}/layouts/${name}.luau")"
	say "layout: prelude, palette, shared helpers, used models, layout"
	{
		cat "${src}/layouts/prelude.luau" "${palette[@]}" "${helpers[@]}"
		# Shared helpers the layout itself calls.
		for included in $(awk '/^-- include: / { print $3 }' "${src}/layouts/${name}.luau"); do
			cat "$(shared_file "${included}")"
		done
		# Builders are globals, not locals: a layout that uses many models
		# (a map's kit can have one per creature) would run past Luau's limit
		# of 200 locals in one function.
		for used in $(head -n 1 "${src}/layouts/${name}.luau" | sed 's/^-- uses://'); do
			echo "function build${used}()"
			cat "${root}/art/models/${used}/model.luau"
			echo "end"
			key="$({ cat "${src}/layouts/prelude.luau" "${root}/art/models/${used}/model.luau"; echo "${skip}"; } | sha1sum | cut -c1-16)"
			echo "buildKeys[build${used}] = \"${used}-${key}\""
			say "uses ${used} (key ${key})"
		done
	} > "${out}.head"
	layout="${src}/layouts/${name}.luau"
	# Each slab body runs from a line ending `slab(..., function()` to the
	# `end` at its indent. Its key hashes the body plus the code it can
	# reach: the prelude, the shared helpers and the layout outside slabs.
	# Not the models the layout uses (a slab can't place one: prelude.luau
	# refuses), nor the `-- uses:` line, nor lines between `-- slab keys
	# skip` and `-- slab keys resume` (the kit), so adding or editing a model
	# leaves every slab cached. Editing one slab rebuilds only that slab;
	# editing shared code rebuilds them all.
	shared_files=()
	while read -r included; do
		shared_files+=("$(shared_file "${included}")")
	done < <(awk '/^-- include: / { print $3 }' "${layout}")
	spans="$(awk '!open && /slab\(.*function\(\)[ \t]*$/ { match($0, /^\t*/); indent = substr($0, 1, RLENGTH); start = NR; open = 1; next }
		open && index($0, indent "end") == 1 { print start, NR; open = 0 }' "${layout}")"
	outside="$(awk -v spans="${spans}" 'BEGIN { n = split(spans, s, /[ \n]/); for (i = 1; i < n; i += 2) for (l = s[i] + 1; l < s[i + 1]; l++) skip[l] = 1 }
		NR == 1 && /^-- uses:/ { next }
		/^-- slab keys skip/ { skipping = 1; next }
		/^-- slab keys resume/ { skipping = 0; next }
		!skip[NR] && !skipping' "${layout}" | cat "${src}/layouts/prelude.luau" "${palette[@]}" "${helpers[@]}" "${shared_files[@]}" - | sha1sum | cut -c1-16)"
	# Measured build times for dealing placements to shards (see prelude.luau),
	# written by the build-map-shards workflow. They go on one line ahead of
	# everything and into no key, so new timings never invalidate the cache.
	costs="${src}/layouts/${name}Costs.txt"
	costs_line="local SHARD_COSTS = { $(if [ -f "${costs}" ]; then awk -F'\t' 'NF == 2 { printf "[\"%s\"] = %s, ", $1, $2 }' "${costs}"; fi) }"
	# Measured paint times for dealing a split model's parts (scripts/paint-costs.sh
	# writes them). Unlike the costs above they change which shard keeps which
	# part, so PAINT_DEAL, a hash of them, goes into each split part's key
	# (prelude.luau). On the same line, so the line numbers below stay put.
	paint_costs="${src}/layouts/${name}PaintCosts.txt"
	costs_line="${costs_line} local PAINT_COSTS: { [string]: number } = { $(if [ -f "${paint_costs}" ]; then awk -F'\t' 'NF == 2 { printf "[\"%s\"] = %s, ", $1, $2 }' "${paint_costs}"; fi) } local PAINT_DEAL = \"$(if [ -f "${paint_costs}" ]; then sha1sum < "${paint_costs}" | cut -c1-12; fi)\""
	offset=$(( 1 + $(wc -l < "${out}.head") + $(printf '%s\n' "${spans}" | grep -c . || true) ))
	{
		echo "${costs_line}"
		cat "${out}.head"
		while read -r start end; do
			[ -n "${start}" ] || continue
			body="$(sed -n "$((start + 1)),$((end - 1))p" "${layout}" | sha1sum | cut -c1-16)"
			echo "slabKeys[$((offset + start))] = \"${outside}-${body}\""
			say "slab at ${layout##*/}:${start}-${end} (key ${body})"
		done <<< "${spans}"
		cat "${layout}"
	} > "${out}"
	rm "${out}.head"
else
	echo "no source for ${name} in art/src" >&2
	exit 1
fi
say "wrote ${out#"${root}/"}, $(wc -l < "${out}") lines, in $((SECONDS - started))s"
