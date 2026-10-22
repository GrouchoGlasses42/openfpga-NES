#!/usr/bin/env python3
"""Extract the actual Pocket filter/output wiring for isolated protocol simulation."""
import argparse
from pathlib import Path


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


if __name__ == "__main__":
    main()
