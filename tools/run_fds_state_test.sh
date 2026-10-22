#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
simulation_root="$(mktemp -d /tmp/nes-fds-state-XXXXXX)"
# Verilator rejects Quartus's constant net-array initializer. A localparam
# array has the same constant values. Quartus also accepts a procedural wire;
# declare that single variable as logic for the simulator. No equations change.
sed -e 's/^wire \[23:0\] BIOS_PATCHES/localparam [23:0] BIOS_PATCHES/' \
    -e 's/^wire \[15:0\] level_out;/logic [15:0] level_out;/' \
    "$project_root/rtl/upstream/mappers/FDS.sv" > "$simulation_root/FDS.sv"
verilator --binary --timing -Wno-fatal --top-module fds_state_tb \
    --Mdir "$simulation_root/obj" \
    "$project_root/rtl/upstream/regs_savestates.sv" \
    "$project_root/tests/ereg_model.sv" \
    "$project_root/target/pocket/audio/filters/iir_filter_tap.sv" \
    "$project_root/target/pocket/audio/filters/iir_filter.sv" \
    "$simulation_root/FDS.sv" "$project_root/tests/fds_state_tb.sv" \
    > "$simulation_root/compile.log" 2>&1 || { tail -60 "$simulation_root/compile.log"; exit 1; }
"$simulation_root/obj/Vfds_state_tb"
