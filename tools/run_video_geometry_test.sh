#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root=${1:-$project_root}
out=${2:?Specify an output directory}
mkdir -p "$out"
python3 "$project_root/tools/prepare_video_regression.py" --source "$source_root" --out "$out"
verilator --binary --timing -j 2 -Wno-fatal --top-module video_geometry_tb \
    --Mdir "$out/obj" "$out/nes_video_ports.sv" "$out/pocket_video_ports.sv" \
    "$out/video.sv" "$source_root/target/pocket/composite_blend.sv" \
    "$source_root/platform/pocket/common.v" "$project_root/tests/video_geometry_tb.sv" \
    > "$out/compile.log" 2>&1
"$out/obj/Vvideo_geometry_tb" > "$out/run.log" 2>&1
cat "$out/run.log"
