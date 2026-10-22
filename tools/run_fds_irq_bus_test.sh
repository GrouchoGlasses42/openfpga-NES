#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root=${1:-$project_root}
out=${2:?Specify an output directory}
mkdir -p "$out"
sed -e 's/^wire \[23:0\] BIOS_PATCHES/localparam [23:0] BIOS_PATCHES/' \
    -e 's/^wire \[15:0\] level_out;/logic [15:0] level_out;/' \
    "$source_root/rtl/upstream/mappers/FDS.sv" > "$out/FDS.sv"
verilator --binary --timing -j 2 -Wno-fatal --top-module fds_irq_bus_tb \
    --Mdir "$out/obj" "$source_root/rtl/upstream/regs_savestates.sv" \
    "$project_root/tests/ereg_model.sv" "$out/FDS.sv" \
    "$project_root/tests/fds_irq_bus_tb.sv" > "$out/compile.log" 2>&1
"$out/obj/Vfds_irq_bus_tb" > "$out/run.log" 2>&1
