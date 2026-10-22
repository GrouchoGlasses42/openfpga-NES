#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root=${1:-$project_root}
out=${2:?Specify output directory}
mkdir -p "$out"
sed -e 's/^wire \[23:0\] BIOS_PATCHES/localparam [23:0] BIOS_PATCHES/' \
    -e 's/^wire \[15:0\] level_out;/logic [15:0] level_out;/' \
    "$source_root/rtl/upstream/mappers/FDS.sv" > "$out/FDS.sv"
verilator --binary --timing -j 2 -Wno-fatal --top-module fds_audio_reset_tb \
    --Mdir "$out/obj" "$out/FDS.sv" \
    "$project_root/tests/fds_audio_reset_tb.sv" > "$out/compile.log" 2>&1
"$out/obj/Vfds_audio_reset_tb" > "$out/run.log" 2>&1
