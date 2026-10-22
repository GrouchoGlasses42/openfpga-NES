`timescale 1ns/1ps
// Check the actual source-extracted output pipeline, including scaler metadata.
module pocket_video_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg [3:0] mode = 0;
  reg hb = 1, vb = 1, hs = 0, vs = 0;
  reg [23:0] rgb = 0;
  reg hide = 0, square = 0;
  wire de_out, hs_out, vs_out, skip_out;
  wire [23:0] rgb_out;
  pocket_video_ports dut (
    .clk_video_5_37(clk), .clk_video_5_37_90deg(~clk),
    .composite_blend_mode(mode), .h_blank(hb), .v_blank(vb),
    .video_hs_nes(hs), .video_vs_nes(vs), .video_rgb_nes(rgb),
    .hide_overscan_with_region(hide), .square_pixels_s(square),
    .video_rgb_clock(), .video_rgb_clock_90(),
    .video_de(de_out), .video_hs(hs_out), .video_vs(vs_out),
    .video_skip(skip_out), .video_rgb(rgb_out)
  );
  reg [2:0] de_history = 0, vs_history = 0;
  reg [9:0] hs_history = 0;
  reg [23:0] rgb_history [0:2];
  reg [23:0] full_history [0:2];
  reg [23:0] left = 0;
  reg left_blank = 1;
  reg previous_de = 0, previous_vs = 0, previous_hs = 0;
  integer cycles = 0, pixels = 0, line_pixels = 0, lines = 0, frames = 0;
  integer since_vs = 100, since_hs = 100;
  reg [23:0] blend;

  function automatic [23:0] avg(input [23:0] a, b);
    integer r,g,blue;
    begin
      r=(integer'(a[23:16])+integer'(b[23:16]))/2;
      g=(integer'(a[15:8])+integer'(b[15:8]))/2;
      blue=(integer'(a[7:0])+integer'(b[7:0]))/2;
      avg={r[7:0],g[7:0],blue[7:0]};
    end
  endfunction

  task automatic cycle(input bit ihb,ivb,ihs,ivs,input [23:0] color);
    begin
      @(negedge clk);
      hb=ihb; vb=ivb; hs=ihs; vs=ivs; rgb=color;
      blend=avg(left_blank ? 24'b0 : left,color);
      @(posedge clk); #1;
      if (cycles>16) begin
        if (de_out !== de_history[2] || vs_out !== (vs_history[2] && !previous_vs))
          $fatal(1,"RGB/DE/VS alignment failure mode=%0d cycle=%0d",mode,cycles);
        if (hs_out !== hs_history[9])
          $fatal(1,"HS delay changed mode=%0d cycle=%0d",mode,cycles);
        if (skip_out !== 0) $fatal(1,"Unexpected skipped pixel");
        if (de_out) begin
          pixels=pixels+1;
          line_pixels=line_pixels+1;
          if (mode==0 && rgb_out !== rgb_history[2])
            $fatal(1,"Off RGB changed or misaligned expected=%06h got=%06h",rgb_history[2],rgb_out);
          if (mode==1 && rgb_out !== full_history[2])
            $fatal(1,"Kitrinx RGB changed or misaligned expected=%06h got=%06h",full_history[2],rgb_out);
        end else if (previous_de) begin
          if (line_pixels != 256) $fatal(1,"Line width %0d instead of 256",line_pixels);
          lines=lines+1; line_pixels=0;
          if (rgb_out !== {9'b0,hide,square,10'b0,3'b0})
            $fatal(1,"Scaler metadata altered by filter mode=%0d RGB=%06h",mode,rgb_out);
        end else if (rgb_out !== 0)
          $fatal(1,"Nonzero RGB outside pixels/metadata mode=%0d RGB=%06h",mode,rgb_out);
        if (vs_out) begin
          if (rgb_out !== 0 || de_out || hs_out) $fatal(1,"Invalid frame-feature word or VS overlap");
          frames=frames+1; since_vs=0;
        end else since_vs=since_vs+1;
        if (hs_out) begin
          if (previous_hs || de_out || since_vs<3) $fatal(1,"HS pulse/VS gap violation");
          since_hs=0;
        end else since_hs=since_hs+1;
        if (de_out && !previous_de && since_hs<2) $fatal(1,"HS to DE gap too short");
      end
      previous_de=de_out; previous_vs=vs_history[2]; previous_hs=hs_out;
      de_history={de_history[1:0],!(ihb||ivb)};
      vs_history={vs_history[1:0],ivs};
      hs_history={hs_history[8:0],ihs};
      rgb_history[2]=rgb_history[1]; rgb_history[1]=rgb_history[0]; rgb_history[0]=color;
      full_history[2]=full_history[1]; full_history[1]=full_history[0]; full_history[0]=blend;
      left=color; left_blank=ihb||ivb;
      cycles=cycles+1;
    end
  endtask

  integer m,f,y,x,pixels_before,lines_before,frames_before;
  initial begin
    for(x=0;x<3;x=x+1) begin rgb_history[x]=0;full_history[x]=0;end
    for(x=0;x<32;x=x+1) cycle(1,1,0,0,0);
    for(m=0;m<=8;m=m+1) begin
      mode=m; hide=(m>>1)&1; square=m&1;
      for(x=0;x<32;x=x+1) cycle(1,1,0,0,0);
      pixels_before=pixels;lines_before=lines;frames_before=frames;
      // Two complete frames exercise PAL first-line invalidation and line reuse.
      for(f=0;f<2;f=f+1) begin
        for(y=0;y<244;y=y+1) begin
          for(x=0;x<341;x=x+1)
            cycle(x<32 || x>=288, y<2 || y>=242,
                  x==0 && y!=0, y==0 && x==0,
                  {8'(x*73+y*31),8'(x*131+y*29),8'(x*17+y*97)});
        end
      end
      for(x=0;x<32;x=x+1) cycle(1,1,0,0,0);
      if (pixels-pixels_before != 256*240*2 || lines-lines_before != 240*2 || frames-frames_before != 2)
        $fatal(1,"Frame geometry changed mode=%0d pixels=%0d lines=%0d frames=%0d",mode,
               pixels-pixels_before,lines-lines_before,frames-frames_before);
      $display("PASS: mode %0d, two 256x240 frames, aligned pixels/sync and scaler metadata",m);
    end
    $display("PASS: Pocket video protocol, %0d cycles and %0d active pixels",cycles,pixels);
    $finish;
  end
endmodule
