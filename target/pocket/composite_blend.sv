// Composite-like horizontal averaging adapted from Kitrinx's cofi.sv in
// opengateware/openFPGA-Genesis. Luma/chroma bandwidth approximation; no waveform encoder.
// Optional PAL modes add line-to-line chroma averaging without waveform decode.
module composite_blend (
    input wire clk,
    input wire [3:0] mode,
    input wire hblank_in,
    input wire vblank_in,
    input wire hsync_in,
    input wire vsync_in,
    input wire dotclk_in,
    input wire interlace_in,
    input wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output reg hblank_out = 1'b1,
    output reg vblank_out = 1'b1,
    output reg hsync_out = 1'b0,
    output reg vsync_out = 1'b0,
    output reg dotclk_out = 1'b0
);
  reg previous_hblank = 1'b1;
  reg previous_vsync = 1'b0;
  reg previous_hsync = 1'b0;
  reg previous_vblank = 1'b1;
  reg previous_dotclk = 1'b0;
  wire blank_in = hblank_in | vblank_in;
  wire frame_boundary = (vsync_in && !previous_vsync) ||
                        (vblank_in && !previous_vblank);
  wire line_start = previous_hblank && !hblank_in && !vblank_in;
  wire line_end = !previous_hblank && hblank_in;

  function automatic [7:0] average2(input [7:0] a, input [7:0] b);
    reg [8:0] sum;
    begin
      sum = {1'b0, a} + {1'b0, b};
      average2 = sum[8:1];
    end
  endfunction

  function automatic [23:0] average_rgb(input [23:0] a, input [23:0] b);
    begin
      average_rgb = {
          average2(a[23:16], b[23:16]),
          average2(a[15:8], b[15:8]),
          average2(a[7:0], b[7:0])
      };
    end
  endfunction

  // Retain the two discarded luma bits so constant colors round-trip exactly.
  // Packed sample: {rounding residue[1:0], Y[7:0], Cr[8:0], Cb[8:0]}.
  function automatic [27:0] separate(input [23:0] rgb);
    reg [9:0] sum;
    reg signed [8:0] cr, cb;
    begin
      sum = {2'b0,rgb[23:16]} + {1'b0,rgb[15:8],1'b0} + {2'b0,rgb[7:0]};
      cr = $signed({1'b0,rgb[23:16]}) - $signed({1'b0,sum[9:2]});
      cb = $signed({1'b0,rgb[7:0]}) - $signed({1'b0,sum[9:2]});
      separate = {sum[1:0],sum[9:2],cr,cb};
    end
  endfunction

  function automatic signed [8:0] chroma3(
      input signed [8:0] right, center, left);
    reg signed [10:0] sum;
    begin
      sum = {{2{right[8]}},right} + {{1{center[8]}},center,1'b0} +
            {{2{left[8]}},left};
      chroma3 = sum >>> 2;
    end
  endfunction

  function automatic signed [8:0] chroma4(
      input signed [8:0] oldest, older, center, right);
    reg signed [10:0] sum;
    begin
      sum = {{2{oldest[8]}},oldest} + {{2{older[8]}},older} +
            {{2{center[8]}},center} + {{2{right[8]}},right};
      chroma4 = sum >>> 2;
    end
  endfunction

  function automatic signed [8:0] chroma2(input signed [8:0] a,b);
    reg signed [9:0] sum;
    begin
      sum = {a[8],a} + {b[8],b};
      chroma2 = sum >>> 1;
    end
  endfunction

  function automatic signed [8:0] chroma_strong(input signed [8:0] box, light);
    reg signed [10:0] sum;
    begin
      // Strong sits halfway between Medium and the full four-tap box.
      sum = {{2{box[8]}},box} + {box[8],box,1'b0} +
            {{2{light[8]}},light};
      chroma_strong = sum >>> 2;
    end
  endfunction

  function automatic signed [8:0] pal_chroma(input signed [8:0] current, previous);
    reg signed [10:0] sum;
    begin
      // 75% current line + 25% previous line; signed floor, no multiplier.
      sum = {{2{current[8]}},current} + {current[8],current,1'b0} +
            {{2{previous[8]}},previous};
      pal_chroma = sum >>> 2;
    end
  endfunction

  function automatic signed [8:0] pal_chroma_strong_plus(
      input signed [8:0] current, previous);
    reg signed [11:0] current_ext, previous_ext, sum;
    begin
      // 5/8 current + 3/8 previous; use shift/add with a signed 12-bit sum.
      current_ext = {{3{current[8]}},current};
      previous_ext = {{3{previous[8]}},previous};
      sum = (current_ext <<< 2) + current_ext +
            (previous_ext <<< 1) + previous_ext;
      pal_chroma_strong_plus = sum >>> 3;
    end
  endfunction

  function automatic [7:0] clip(input signed [10:0] value);
    begin
      if (value < 0) clip = 8'h00;
      else if (value > 255) clip = 8'hff;
      else clip = value[7:0];
    end
  endfunction

  reg [9:0] pixel_count = 0;
  reg write_bank = 0;
  reg pal_have_line = 0;
  reg pal_line_valid = 0;
  reg pal_line_mode_changed = 0;
  reg [3:0] pal_current_line_mode = 0;
  reg [3:0] pal_completed_line_mode = 0;
  reg [9:0] pal_completed_line_length = 0;

  // Previous samples are the center and left taps for the current right tap.
  reg [27:0] pixel_d1 = 0, pixel_d2 = 0, pixel_d3 = 0;
  reg [3:0] previous_mode = 0;
  wire mode_changed = mode != previous_mode;
  reg [2:0] horizontal_valid = 0;
  reg [23:0] raw_previous = 0;

  // Preserve Full's original black-left-edge two-pixel average exactly.
  reg [23:0] full_previous = 0;
  reg full_previous_blank = 1'b1;
  reg [23:0] full_result_previous = 0;
  wire [23:0] full_result_current = average_rgb(
      full_previous_blank ? 24'b0 : full_previous,
      rgb_in
  );

  wire [27:0] input_sample = separate(rgb_in);
  wire [27:0] right_tap = blank_in ? pixel_d1 : input_sample;
  wire [27:0] left_tap_1 = horizontal_valid >= 2 && !mode_changed ? pixel_d2 : pixel_d1;
  wire [27:0] left_tap_2 = horizontal_valid >= 3 && !mode_changed ? pixel_d3 : left_tap_1;
  wire signed [8:0] cb1 = chroma3(right_tap[8:0],pixel_d1[8:0],left_tap_1[8:0]);
  wire signed [8:0] cr1 = chroma3(right_tap[17:9],pixel_d1[17:9],left_tap_1[17:9]);
  // Same four equal taps and half-pixel chroma phase as the RGB NTSC3 kernel.
  wire signed [8:0] cb3 = chroma4(left_tap_2[8:0],left_tap_1[8:0],pixel_d1[8:0],right_tap[8:0]);
  wire signed [8:0] cr3 = chroma4(left_tap_2[17:9],left_tap_1[17:9],pixel_d1[17:9],right_tap[17:9]);
  wire signed [8:0] cb2 = chroma2(cb1,cb3);
  wire signed [8:0] cr2 = chroma2(cr1,cr3);
  // Filter the full luma numerator, including its two fractional bits.
  // This makes strength changes visible in monochrome dithering too, while
  // keeping NTSC1/2 luma narrower than their chroma kernels.
  wire [9:0] y_right = {right_tap[25:18],right_tap[27:26]};
  wire [9:0] y_center = {pixel_d1[25:18],pixel_d1[27:26]};
  wire [9:0] y_left = {left_tap_1[25:18],left_tap_1[27:26]};
  wire [9:0] y_oldest = {left_tap_2[25:18],left_tap_2[27:26]};
  wire [11:0] y_121_sum = {2'b0,y_right} + {1'b0,y_center,1'b0} + {2'b0,y_left};
  wire [12:0] y_161_sum = {1'b0,y_121_sum} + {1'b0,y_center,2'b0};
  wire [11:0] y_box_sum = {2'b0,y_oldest} + {2'b0,y_left} +
                         {2'b0,y_center} + {2'b0,y_right};
  wire [9:0] y_light = y_161_sum[12:3];
  wire [9:0] y_box = y_box_sum[11:2];
  wire [10:0] y_mid_sum = {1'b0,y_light} + {1'b0,y_box};
  wire [11:0] y_strong_sum = {2'b0,y_box} + {1'b0,y_box,1'b0} + {2'b0,y_light};
  wire [9:0] y_strong = y_strong_sum[11:2];
  // Midpoint keeps a visibly distinct response even on one-pixel checkerboards.
  wire [9:0] selected_y = (mode == 4'd4 || mode >= 4'd7) ? y_strong :
                         (mode == 4'd3 || mode == 4'd6) ? y_mid_sum[10:1] : y_light;
  wire is_pal_mode = (mode >= 4'd5);
  // PAL Light/Medium use one stronger chroma kernel than matching NTSC luma;
  // PAL Strong keeps box-filtered chroma and retuned strong luma.
  // This preserves sharp brightness detail and distinguishes repeated rows
  // without increasing the previous-line chroma contribution.
  wire signed [8:0] cb_strong = chroma_strong(cb3,cb1);
  wire signed [8:0] cr_strong = chroma_strong(cr3,cr1);
  wire signed [8:0] selected_cb = (mode == 4'd4) ? cb_strong :
                                  (mode >= 4'd6) ? cb3 :
                                  (mode == 4'd3 || mode == 4'd5) ? cb2 : cb1;
  wire signed [8:0] selected_cr = (mode == 4'd4) ? cr_strong :
                                  (mode >= 4'd6) ? cr3 :
                                  (mode == 4'd3 || mode == 4'd5) ? cr2 : cr1;
  // Store unblended horizontal chroma, never the previous vertical result.
  wire [19:0] pal_write_data = {selected_cr[8],selected_cr,selected_cb[8],selected_cb};
  wire [8:0] center_addr = pixel_count[8:0] - 9'd1;
  wire center_valid = (pixel_count != 0) && (pixel_count <= 512);

  (* ramstyle = "M10K" *) reg [19:0] pal_mem0 [0:511];
  (* ramstyle = "M10K" *) reg [19:0] pal_mem1 [0:511];
  // Independent synchronous read registers are required for Quartus M10K inference.
  // Delay the bank selector alongside the data so the preceding line stays aligned.
  reg [19:0] pal_read0 = 0, pal_read1 = 0;
  reg pal_read_bank = 0;
  wire [19:0] pal_previous_line = pal_read_bank ? pal_read0 : pal_read1;
  reg [7:0] y_previous = 0;
  reg [1:0] residue_previous = 0;
  reg signed [8:0] cb_previous = 0, cr_previous = 0;
  reg pal_vertical_mix = 0;
  reg pal_strong_plus_mix = 0;
  wire signed [8:0] output_cb = pal_vertical_mix ?
      (pal_strong_plus_mix ? pal_chroma_strong_plus(cb_previous,pal_previous_line[8:0]) :
                       pal_chroma(cb_previous,pal_previous_line[8:0])) : cb_previous;
  wire signed [8:0] output_cr = pal_vertical_mix ?
      (pal_strong_plus_mix ? pal_chroma_strong_plus(cr_previous,pal_previous_line[18:10]) :
                       pal_chroma(cr_previous,pal_previous_line[18:10])) : cr_previous;
  wire signed [10:0] y_extended = $signed({3'b0,y_previous});
  wire signed [10:0] cb_extended = {{2{output_cb[8]}},output_cb};
  wire signed [10:0] cr_extended = {{2{output_cr[8]}},output_cr};
  wire signed [10:0] r_result = y_extended + cr_extended;
  wire signed [10:0] b_result = y_extended + cb_extended;
  wire signed [10:0] g_result = y_extended -
      ((cb_extended + cr_extended - $signed({9'b0,residue_previous})) >>> 1);
  wire [23:0] filtered_rgb = {clip(r_result),clip(g_result),clip(b_result)};
  reg [23:0] rgb_nonfilter_out = 0;
  reg filter_mode_out = 0;
  assign rgb_out = filter_mode_out ? filtered_rgb : rgb_nonfilter_out;

  // Each bank has one synchronous read port and one write port. The banks
  // alternate by line so the read always sees the preceding line's chroma.
  always @(posedge clk) begin
    if (center_valid && !write_bank) pal_mem0[center_addr] <= pal_write_data;
    if (center_valid && write_bank)  pal_mem1[center_addr] <= pal_write_data;
    pal_read0 <= pal_mem0[center_addr];
    pal_read1 <= pal_mem1[center_addr];
    pal_read_bank <= write_bank;
  end

  always @(posedge clk) begin
    hblank_out <= previous_hblank;
    vblank_out <= previous_vblank;
    hsync_out <= previous_hsync;
    vsync_out <= previous_vsync;
    dotclk_out <= previous_dotclk;
    previous_hblank <= hblank_in;
    previous_vblank <= vblank_in;
    previous_hsync <= hsync_in;
    previous_vsync <= vsync_in;
    previous_dotclk <= dotclk_in;

    full_previous <= rgb_in;
    full_previous_blank <= blank_in;
    full_result_previous <= full_result_current;

    previous_mode <= mode;
    pal_strong_plus_mix <= mode == 4'd8;
    filter_mode_out <= mode >= 4'd2;
    y_previous <= selected_y[9:2];
    // Keep the source's RGB rounding residue. A fractional filtered Y must
    // not turn neutral gray into green when both chroma channels are zero.
    residue_previous <= pixel_d1[27:26];
    cb_previous <= selected_cb;
    cr_previous <= selected_cr;
    pal_vertical_mix <= pal_line_valid && is_pal_mode && !interlace_in &&
                        !frame_boundary && !mode_changed &&
                        (pal_current_line_mode == mode) && !pal_line_mode_changed &&
                        center_valid && (center_addr < pal_completed_line_length);
    rgb_nonfilter_out <= mode == 4'd1 ? full_result_previous : raw_previous;
    raw_previous <= rgb_in;

    if (blank_in) begin
      pixel_d1 <= 0;
      pixel_d2 <= 0;
      pixel_d3 <= 0;
      horizontal_valid <= 0;
      pixel_count <= 0;
    end else begin
      pixel_d3 <= pixel_d2;
      pixel_d2 <= pixel_d1;
      pixel_d1 <= input_sample;
      if (mode_changed) begin
        pixel_d2 <= input_sample;
        pixel_d3 <= input_sample;
        horizontal_valid <= 1;
      end else if (horizontal_valid != 3) horizontal_valid <= horizontal_valid + 1'b1;
      if (pixel_count < 1023) pixel_count <= pixel_count + 1'b1;
    end

    if (frame_boundary) begin
      write_bank <= 0;
      pal_have_line <= 0;
      pal_line_valid <= 0;
      pal_current_line_mode <= 0;
      pal_completed_line_mode <= 0;
      pal_completed_line_length <= 0;
      pal_line_mode_changed <= 0;
    end else begin
      if (line_start) begin
        write_bank <= ~write_bank;
        pal_current_line_mode <= mode;
        pal_line_valid <= pal_have_line && (pal_completed_line_mode == mode) && is_pal_mode;
        pal_line_mode_changed <= 0;
      end else if (mode != pal_current_line_mode) begin
        pal_line_mode_changed <= 1;
      end
      if (line_end) begin
        if ((pixel_count != 0) && (pal_current_line_mode == mode) &&
            !pal_line_mode_changed && is_pal_mode) begin
          pal_have_line <= 1;
          pal_completed_line_mode <= mode;
          pal_completed_line_length <= pixel_count > 512 ? 10'd512 : pixel_count;
        end else begin
          pal_have_line <= 0;
          pal_line_valid <= 0;
          pal_completed_line_length <= 0;
        end
      end
      // A transient menu change during blanking must also discard PAL history.
      if (mode_changed) begin
        pal_have_line <= 0;
        pal_line_valid <= 0;
        pal_completed_line_length <= 0;
      end
    end
  end
endmodule
