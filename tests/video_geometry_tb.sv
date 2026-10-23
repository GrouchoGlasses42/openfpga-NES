`timescale 1ns/1ps
// Exercise the production NES video instance and Pocket output wiring together.
// Each source row has a distinct gray value. This checks the crop position as
// well as frame dimensions, including the PAL filters and scaler metadata.
module video_geometry_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg [1:0] cnt = 0;
  wire pixel_clk = cnt[1];
  reg [8:0] x = 0, y = 511;
  reg reset = 1;
  reg hide = 0, square = 0;
  reg [3:0] mode = 0;
  reg write_palette = 0;
  reg [5:0] palette_index = 0;
  reg [23:0] palette_color = 0;
  wire hb, vb, hs, vs;
  wire [23:0] nes_rgb, rgb;
  wire de, pocket_hs, pocket_vs;
  nes_video_ports generator (
    .clk_ppu_21_47(clk), .reset_nes(reset), .nes_ce_video(cnt),
    .sys_type(2'b00), .color(y[5:0]), .scanline(y), .cycle(x),
    .hide_overscan(hide), .selected_palette(3'd5), .emphasis(3'd0),
    .pal_write(write_palette), .pal_color(palette_color), .pal_index(palette_index),
    .lightgun_enabled(1'b0), .reticle(2'd0), .pal_video(1'b0),
    .hold_reset(), .HSync(hs), .VSync(vs), .HBlank(hb), .VBlank(vb),
    .video_r(nes_rgb[23:16]), .video_g(nes_rgb[15:8]), .video_b(nes_rgb[7:0])
  );
  pocket_video_ports output_ports (
    .clk_video_5_37(pixel_clk), .clk_video_5_37_90deg(~pixel_clk),
    .composite_blend_mode(mode), .h_blank(hb), .v_blank(vb),
    .video_hs_nes(hs), .video_vs_nes(vs), .video_rgb_nes(nes_rgb),
    .hide_overscan_with_region(hide), .square_pixels_s(square),
    .video_rgb_clock(), .video_rgb_clock_90(),
    .video_de(de), .video_hs(pocket_hs), .video_vs(pocket_vs),
    .video_skip(), .video_rgb(rgb)
  );

  // NES dot counters advance once per four master clocks, as in NTSC mode.
  always @(negedge clk) begin
    cnt <= cnt + 1'b1;
    if (cnt == 3) begin
      if (x == 340) begin
        x <= 0;
        y <= y == 260 ? 9'd511 : y + 1'b1;
      end else x <= x + 1'b1;
    end
  end

  integer lines = 0, pixels = 0, completed = 0;
  integer height, source_row, expected_gray;
  reg checking = 0, previous_de = 0;
  always @(posedge pixel_clk) begin
    #1;
    if (checking) begin
      if (de) begin
        pixels = pixels + 1;
        // Sample well inside the line, beyond the horizontal filter taps.
        if (pixels == 128) begin
          source_row = lines + (hide ? 8 : 0);
          expected_gray = ((source_row % 64) + 1) * 3;
          if (rgb !== {3{8'(expected_gray)}})
            $fatal(1,"Crop position mode=%0d hide=%0d line=%0d source_row=%0d expected=%06h got=%06h",
                   mode,hide,lines,source_row,{3{8'(expected_gray)}},rgb);
        end
      end
      if (!de && previous_de) begin
        if (pixels != 256) $fatal(1,"Line width %0d",pixels);
        if (rgb !== {9'd0,hide,square,13'd0})
          $fatal(1,"Wrong scaler mode mode=%0d hide=%0d square=%0d rgb=%06h",mode,hide,square,rgb);
        pixels = 0;
        lines = lines + 1;
      end
      if (pocket_vs) begin
        height = hide ? 224 : 240;
        if (lines != height || pixels != 0)
          $fatal(1,"Frame height mode=%0d hide=%0d expected=%0d got=%0d",mode,hide,height,lines);
        if (de || pocket_hs || rgb != 0) $fatal(1,"Invalid frame boundary");
        lines = 0;
        completed = completed + 1;
      end
    end
    previous_de = de;
  end

  task automatic wait_vsync;
    begin
      do begin @(posedge pixel_clk); #2; end while (!pocket_vs);
    end
  endtask

  integer i,m,h,s,gray;
  initial begin
    for (i=0;i<64;i=i+1) begin
      @(posedge clk); #2;
      gray=(i+1)*3;
      write_palette=1; palette_index=6'(i); palette_color={3{8'(gray)}};
    end
    @(posedge clk); #2; write_palette=0; reset=0;
    for (m=0;m<=8;m=m+1)
      for (h=0;h<=1;h=h+1)
        for (s=0;s<=1;s=s+1) begin
          checking=0; mode=4'(m); hide=1'(h); square=1'(s);
          // Permit setting synchronization and the in-progress frame to finish.
          wait_vsync();
          @(posedge pixel_clk); #2;
          lines=0; pixels=0; completed=0; checking=1;
          wait (completed == 2);
          @(posedge pixel_clk); #2; checking=0;
          $display("PASS mode=%0d hide=%0d square=%0d: two 256x%0d frames, rows %0d..%0d, matching scaler mode",
                   mode,hide,square,hide ? 224 : 240,hide ? 8 : 0,hide ? 231 : 239);
        end
    $display("PASS: all 36 video settings and centered crops");
    $finish;
  end
  initial begin
    repeat (500) #1000000;
    $fatal(1,"Video geometry test timed out");
  end
endmodule

// Synchronous palette RAM model; the test writes every location before use.
module spram #(
    parameter addr_width=6, data_width=24, mem_name="", mem_init_file=""
) (
    input clock, input [addr_width-1:0] address,
    input [data_width-1:0] data, input wren,
    output reg [data_width-1:0] q
);
  reg [data_width-1:0] memory [0:(1<<addr_width)-1];
  always @(posedge clock) begin
    if (wren) memory[address] <= data;
    q <= memory[address];
  end
endmodule
