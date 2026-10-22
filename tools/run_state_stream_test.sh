#!/bin/bash
set -euo pipefail
source_root=${1:?Source directory}
out=${2:?Output directory}
mode=${3:-fixed}
mkdir -p "$out"
python3 /workspace/pocket-nes/tools/prepare_save_regression.py --source "$source_root" --out "$out"
ghdl --synth --std=08 -fsynopsys --out=verilog \
  "$source_root/rtl/upstream/bus_savestates.vhd" \
  "$source_root/rtl/upstream/savestates.vhd" -e savestates \
  > "$out/savestates-raw.v" 2> "$out/ghdl.log"
python3 - "$out" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]);s=(p/'savestates-raw.v').read_text()
s=re.sub(r'"([01]+)"',lambda m:str(len(m[1]))+"'b"+m[1],s)
(p/'savestates.v').write_text(s)
PY
defines=()
if grep -q 'input wire ss_load_done' "$source_root/target/pocket/save_state_controller.sv"; then
  defines+=(-DSTATE_DONE_CHECK)
fi
verilator --binary --timing -j 4 -Wno-fatal "${defines[@]}" --top-module state_stream_tb \
  --Mdir "$out/obj" "$out/savestates.v" "$out/sdram.sv" \
  "$source_root/target/pocket/save_state_controller.sv" \
  /workspace/pocket-nes/platform/pocket/common.v \
  /workspace/pocket-nes/tests/pocket_fifo_model.sv \
  /workspace/pocket-nes/tests/sdram_pin_model.sv \
  /workspace/pocket-nes/tests/state_stream_tb.sv \
  > "$out/compile.log" 2>&1 || { tail -60 "$out/compile.log"; exit 1; }
"$out/obj/Vstate_stream_tb" "+$mode" > "$out/run.log" 2>&1
cat "$out/run.log"
