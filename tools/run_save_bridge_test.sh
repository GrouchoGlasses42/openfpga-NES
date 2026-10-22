#!/bin/bash
set -euo pipefail
out=${1:?Prepared output directory}
mode=${2:-fixed}
shift 2
extra=()
if [ -f "$out/save_transfer_controller.sv" ]; then
  extra=(-DGUARDED_TRANSFER "$out/save_transfer_controller.sv" "$out/synch_3.v")
fi
verilator --binary --timing -j 4 -Wno-fatal --top-module save_bridge_tb \
  "${extra[@]}" \
  --Mdir "$out/obj" "$out/save_bridge_ports.sv" "$out/sdram.sv" \
  "$out/data_loader.sv" "$out/data_unloader.sv" \
  /workspace/pocket-nes/tests/pocket_fifo_model.sv \
  /workspace/pocket-nes/tests/save_bridge_tb.sv \
  > "$out/compile.log" 2>&1 || { tail -50 "$out/compile.log"; exit 1; }
"$out/obj/Vsave_bridge_tb" "+$mode" "$@" > "$out/run.log" 2>&1
cat "$out/run.log"
