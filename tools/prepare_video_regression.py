#!/usr/bin/env python3
"""Extract the actual Pocket filter/output wiring for isolated protocol simulation."""
import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source = (args.source / "target/pocket/core_top.v").read_text()
    assert "composite_blend_mode <= bridge_wr_data[3:0];" in source
    start = source.index("  // All nine modes delay RGB")
    end = source.index("  // Sound", start)
    header = """module pocket_video_ports (
  input wire clk_video_5_37, clk_video_5_37_90deg,
  input wire [3:0] composite_blend_mode,
  input wire h_blank, v_blank, video_hs_nes, video_vs_nes,
  input wire [23:0] video_rgb_nes,
  input wire hide_overscan_with_region, square_pixels_s,
  output wire video_rgb_clock, video_rgb_clock_90,
  output wire video_de, video_hs, video_vs, video_skip,
  output wire [23:0] video_rgb
);
"""
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "pocket_video_ports.sv").write_text(header + source[start:end] + "endmodule\n")
    # Include the production mode mapping, rather than synthesizing blanking in
    # the test bench. This catches mismatches between DE and the scaler height.
    source = (args.source / "rtl/nes_top.sv").read_text()
    start = source.index("  video video (")
    end = source.index("\n  );", start) + len("\n  );")
    header = """module nes_video_ports (
  input wire clk_ppu_21_47, reset_nes,
  input wire [1:0] nes_ce_video, sys_type,
  input wire [5:0] color,
  input wire [8:0] scanline, cycle,
  input wire hide_overscan,
  input wire [2:0] selected_palette, emphasis,
  input wire pal_write,
  input wire [23:0] pal_color,
  input wire [5:0] pal_index,
  input wire lightgun_enabled,
  input wire [1:0] reticle,
  input wire pal_video,
  output wire hold_reset, HSync, VSync, HBlank, VBlank,
  output wire [7:0] video_r, video_g, video_b
);
"""
    (args.out / "nes_video_ports.sv").write_text(header + source[start:end] + "\nendmodule\n")
    # Quartus accepts constant unpacked net-array initializers. Verilator 5.006
    # requires these lookup tables to be declared as localparam arrays instead.
    source = (args.source / "rtl/upstream/video.sv").read_text()
    source = re.sub(r"^wire (\[[^\]]+\] (?:pal_\w+_lut|lut_2c04_\d+)\[64\] =)",
                    r"localparam \1", source, flags=re.M)
    source = source.replace("wire [8:0] vblank_start,", "logic [8:0] vblank_start,")
    source = source.replace("wire [8:0] vblank_start_sl,", "logic [8:0] vblank_start_sl,")
    source = source.replace("wire hblank_period;", "logic hblank_period;")
    (args.out / "video.sv").write_text(source)


if __name__ == "__main__":
    main()
