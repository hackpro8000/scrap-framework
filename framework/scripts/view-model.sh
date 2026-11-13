#!/usr/bin/env bash
# Renders a model from four angles side by side, for checking work without
# a full checkpoint.
#
#   framework/scripts/view-model.sh Crate /tmp/crate.png

set -euo pipefail

name="${1:?model name required}"
out="${2:?output png required}"
source "$(dirname "$0")/lib/game.sh"
root="${GAME_ROOT}"
turntable="${root}/art/models/${name}/turntable"

"${FRAMEWORK}/engine/bin/modelkit-linux-x64" "${root}/art/models/${name}" --turntable 60 >/dev/null
ffmpeg -loglevel error -y -i "${turntable}/0000.png" -i "${turntable}/0015.png" -i "${turntable}/0030.png" -i "${turntable}/0045.png" -filter_complex hstack=4 "${out}"
rm -rf "${turntable}"
