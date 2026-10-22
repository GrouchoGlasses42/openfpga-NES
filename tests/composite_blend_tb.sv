`timescale 1ns/1ps
// Self-checking streaming testbench for composite_blend. The reference model
// uses integer signed Y/Cb/Cr arithmetic and independently models the old
// RGB-domain filters used for Off/Full and numerical comparisons.
module composite_blend_tb;
  reg clk = 0;
  reg [3:0] mode = 0;
  reg hblank_in = 1, vblank_in = 1;
  reg hsync_in = 0, vsync_in = 0, dotclk_in = 0, interlace_in = 0;
  reg [23:0] rgb_in = 0;
  wire [23:0] rgb_out;
  wire hblank_out, vblank_out, hsync_out, vsync_out, dotclk_out;
  reg [23:0] pixels [0:520];
  reg [23:0] previous_line [0:520];
  reg last_hb = 1, last_vb = 1, last_hs = 0, last_vs = 0, last_dot = 0;
  integer checks = 0;
  integer underflow_outputs = 0, overflow_outputs = 0;
  integer actual_luma [0:520];
  reg [23:0] colored_dither [0:7][0:520];
  reg [23:0] repeated_pal_dither [5:8][0:23];
  reg [23:0] neutral_gray [0:8][0:520];
  integer pal7_vertical_differences=0, pal8_vertical_differences=0;
  integer gray_line_active=0, gray_previous_line=0, gray_check_enable=0;
  integer previous_width = 0;
  integer line_number = 0;

  composite_blend dut(.*);
  always #5 clk = ~clk;

  function automatic integer clip8(input integer x);
    if (x < 0) clip8 = 0;
    else if (x > 255) clip8 = 255;
    else clip8 = x;
  endfunction

  function automatic integer signed floorhalf(input integer signed x);
    floorhalf = x >>> 1;
  endfunction

  function automatic integer component(input [23:0] rgb, input integer c);
    case (c)
      0: component = rgb[23:16];
      1: component = rgb[15:8];
      default: component = rgb[7:0];
    endcase
  endfunction

  function automatic integer y_of(input [23:0] rgb);
    integer r,g,b;
    begin
      r=rgb[23:16]; g=rgb[15:8]; b=rgb[7:0];
      y_of=(r+2*g+b) >> 2;
    end
  endfunction

  function automatic integer signed c_of(input [23:0] rgb, input integer is_cr);
    integer y;
    begin
      y=y_of(rgb);
      c_of=is_cr ? integer'(rgb[23:16])-y : integer'(rgb[7:0])-y;
    end
  endfunction

  function automatic [7:0] avg2c(input [7:0] a,input [7:0] b);
    avg2c=({1'b0,a}+{1'b0,b}) >> 1;
  endfunction
  function automatic [7:0] avg3c(input [7:0] a,input [7:0] b,input [7:0] c);
    avg3c=({2'b0,a}+{1'b0,b,1'b0}+{2'b0,c}) >> 2;
  endfunction
  function automatic [7:0] avg4c(input [7:0] a,input [7:0] b,input [7:0] c,input [7:0] d);
    avg4c=({2'b0,a}+{2'b0,b}+{2'b0,c}+{2'b0,d}) >> 2;
  endfunction
  function automatic [23:0] avg2rgb(input [23:0] a,input [23:0] b);
    avg2rgb={avg2c(a[23:16],b[23:16]),avg2c(a[15:8],b[15:8]),avg2c(a[7:0],b[7:0])};
  endfunction
  function automatic [23:0] avg3rgb(input [23:0] a,input [23:0] b,input [23:0] c);
    avg3rgb={avg3c(a[23:16],b[23:16],c[23:16]),avg3c(a[15:8],b[15:8],c[15:8]),avg3c(a[7:0],b[7:0],c[7:0])};
  endfunction
  function automatic [23:0] avg4rgb(input [23:0] a,input [23:0] b,input [23:0] c,input [23:0] d);
    avg4rgb={avg4c(a[23:16],b[23:16],c[23:16],d[23:16]),avg4c(a[15:8],b[15:8],c[15:8],d[15:8]),avg4c(a[7:0],b[7:0],c[7:0],d[7:0])};
  endfunction

  // Read a test line with endpoint clamping. prev=0 selects the active line;
  // prev=1 selects the preceding line used by the PAL vertical model.
  function automatic [23:0] sample(input integer x,input integer width,input integer prev);
    integer p;
    begin
      p=x;
      if (p<0) p=0;
      if (p>=width) p=width-1;
      sample=prev ? previous_line[p] : pixels[p];
    end
  endfunction

  function automatic integer signed chroma_tap(input integer x,input integer width,
                                                   input integer prev,input integer is_cr);
    chroma_tap=c_of(sample(x,width,prev),is_cr);
  endfunction

  // The luma kernels average the full 10-bit R+2G+B sum, retaining its low
  // two bits as the reconstruction residue. Strong is a 3:1 blend of the
  // four-tap box and Light response, which preserves a visible ladder step.
  function automatic integer filtered_luma_q2(input [3:0] m,input integer x,input integer width);
    integer a,b,c,d;
    begin
      a=component(sample(x-2,width,0),0)+2*component(sample(x-2,width,0),1)+component(sample(x-2,width,0),2);
      b=component(sample(x-1,width,0),0)+2*component(sample(x-1,width,0),1)+component(sample(x-1,width,0),2);
      c=component(sample(x,width,0),0)+2*component(sample(x,width,0),1)+component(sample(x,width,0),2);
      d=component(sample(x+1,width,0),0)+2*component(sample(x+1,width,0),1)+component(sample(x+1,width,0),2);
      case(m)
        2,5: filtered_luma_q2=(b+6*c+d) >>> 3;
        3,6: filtered_luma_q2=(((b+6*c+d) >>> 3)+((a+b+c+d) >>> 2)) >>> 1;
        4,7,8: filtered_luma_q2=(3*((a+b+c+d) >>> 2)+((b+6*c+d) >>> 3)) >>> 2;
        default: filtered_luma_q2=c;
      endcase
    end
  endfunction

  // Mode 2/5 uses 1:2:1; mode 3/6 is its midpoint with the four-tap box.
  // NTSC Strong blends that box 3:1 with Light. PAL 6/7/8 keep the box.
  function automatic integer signed filtered_chroma(input [3:0] m,input integer x,
                                                        input integer width,input integer prev,
                                                        input integer is_cr);
    integer signed n1,n3;
    begin
      n1=chroma_tap(x+1,width,prev,is_cr)+2*chroma_tap(x,width,prev,is_cr)+chroma_tap(x-1,width,prev,is_cr);
      n1=n1 >>> 2;
      n3=chroma_tap(x-2,width,prev,is_cr)+chroma_tap(x-1,width,prev,is_cr)+
         chroma_tap(x,width,prev,is_cr)+chroma_tap(x+1,width,prev,is_cr);
      n3=n3 >>> 2;
      case (m)
        2: filtered_chroma=n1;
        3,5: filtered_chroma=floorhalf(n1+n3);
        4: filtered_chroma=(3*n3+n1) >>> 2;
        6,7,8: filtered_chroma=n3;
        default: filtered_chroma=chroma_tap(x,width,prev,is_cr);
      endcase
    end
  endfunction

  function automatic [23:0] encode_ycc(input integer y,input integer signed cr,
                                          input integer signed cb,input integer residue);
    integer r,g,b;
    begin
      r=clip8(y+cr); b=clip8(y+cb);
      g=clip8(y-floorhalf(cr+cb-residue));
      encode_ycc={r[7:0],g[7:0],b[7:0]};
    end
  endfunction

  function automatic [23:0] ycc_pixel(input [3:0] m,input integer x,input integer width,
                                         input integer do_pal,input integer prev_width);
    reg [23:0] center;
    integer y,residue,sum;
    integer signed cr,cb,pcr,pcb;
    begin
      center=sample(x,width,0);
      sum=filtered_luma_q2(m,x,width);
      y=sum >> 2;
      residue=(center[23:16]+2*center[15:8]+center[7:0]) & 3;
      cr=filtered_chroma(m,x,width,0,1);
      cb=filtered_chroma(m,x,width,0,0);
      if (do_pal && previous_width>0) begin
        pcr=filtered_chroma(m,x,prev_width,1,1);
        pcb=filtered_chroma(m,x,prev_width,1,0);
        if (m==8) begin cr=(5*cr+3*pcr) >>> 3; cb=(5*cb+3*pcb) >>> 3; end
        else begin cr=(3*cr+pcr) >>> 2; cb=(3*cb+pcb) >>> 2; end
      end
      ycc_pixel=encode_ycc(y,cr,cb,residue);
    end
  endfunction

  // Legacy RGB-domain response, used for direct numeric comparison and for
  // preserving the Off/Full behavior.
  function automatic [23:0] old_rgb_pixel(input [3:0] m,input integer x,input integer width);
    reg [23:0] l2,l1,c,r,n1,n3;
    begin
      l2=sample(x-2,width,0); l1=sample(x-1,width,0);
      c=sample(x,width,0); r=sample(x+1,width,0);
      n1=avg3rgb(r,c,l1); n3=avg4rgb(l2,l1,c,r);
      case(m)
        0: old_rgb_pixel=c;
        1: old_rgb_pixel=avg2rgb((x>0)?sample(x-1,width,0):24'h000000,c);
        2,5: old_rgb_pixel=n1;
        3,6: old_rgb_pixel=avg2rgb(n1,n3);
        4: old_rgb_pixel=n3;
        default: old_rgb_pixel=c;
      endcase
    end
  endfunction

  function automatic [23:0] expected_pixel(input [3:0] m,input integer x,input integer width,
                                              input integer pal_valid,input integer intl);
    begin
      if (m==0 || m==1) expected_pixel=old_rgb_pixel(m,x,width);
      else expected_pixel=ycc_pixel(m,x,width,(m>=5 && pal_valid && !intl && x<previous_width),previous_width);
    end
  endfunction

  // Seven test scenes: solid color, monochrome edge, saturated RGB bars,
  // checkerboard, two-level dither, clipping extremes, deterministic noise.
  function automatic [23:0] scene(input integer which,input integer x,input integer row);
    integer v,g,b;
    begin
      case(which)
        0: case(row%4)
             0: scene=24'h000000; 1: scene=24'hffffff;
             2: scene=24'h804020; default: scene=24'h33cc99;
           endcase
        1: scene=(x<16)?24'h000000:24'hffffff;
        2: case((x/4)%3)
             0: scene=24'hff0000; 1: scene=24'h00ff00; default: scene=24'h0000ff;
           endcase
        3: scene=((x+row)&1)?24'hffffff:24'h000000;
        4: scene=((x%4)<2)?24'hff00ff:24'h00ffff;
        5: case(x%8)
             0: scene=24'hff0000; 1: scene=24'h00ff00; 2: scene=24'h0000ff; 3: scene=24'hffff00;
             4: scene=24'h00ffff; 5: scene=24'hff00ff; 6: scene=24'hffffff; default: scene=24'h000000;
           endcase
        7: case(row%5)
             0: scene=24'h000000; 1: scene=24'hffffff; 2: scene=24'hff0000;
             3: scene=24'h00ff00; default: scene=24'h0000ff;
           endcase
        8: scene=24'h7b2de5; // odd arbitrary channels exercise residue preservation
        9: scene=((x%4)<2)?24'hff00ff:24'h00ff00; // matched-luma 2-on/2-off chroma
        10: scene=((x%4)<2)?24'h000000:24'hffffff; // monochrome luma strength pattern
        11: scene=(row&1)?24'hffffff:24'h000000;
        12: scene=(x&1)?24'hffffff:24'h000000; // monochrome one-pixel checker
        13: begin
          v=(x*255)/23;
          scene={v[7:0],v[7:0],v[7:0]}; // grayscale ramp, no source chroma
        end
        default: begin
          v=(x*73+row*151+x*row*19+37)&255;
          g=(x*131+row*29+11)&255; b=(x*17+row*97+201)&255;
          scene={v[7:0],g[7:0],b[7:0]};
        end
      endcase
    end
  endfunction

  task automatic cycle(input [3:0] m,input bit hb,vb,hs,vs,dotc,intl,
                       input [23:0] color,input bit compare_rgb,input [23:0] expected);
    begin
      @(negedge clk);
      mode=m; hblank_in=hb; vblank_in=vb; hsync_in=hs; vsync_in=vs;
      dotclk_in=dotc; interlace_in=intl; rgb_in=color;
      @(posedge clk); #1;
      if (hblank_out !== last_hb || vblank_out !== last_vb || hsync_out !== last_hs ||
          vsync_out !== last_vs || dotclk_out !== last_dot)
        $fatal(1,"metadata latency mismatch at check %0d",checks);
      if (compare_rgb && rgb_out !== expected)
        $fatal(1,"RGB mismatch check=%0d line=%0d mode=%0d hb=%b input=%06h expected=%06h got=%06h intl=%b Y=%0d Cb=%0d Cr=%0d mix=%b prevCb=%0d prevCr=%0d outCb=%0d outCr=%0d addr=%0d len=%0d",checks,line_number,m,hb,color,expected,rgb_out,interlace_in,dut.y_previous,$signed(dut.cb_previous),$signed(dut.cr_previous),dut.pal_vertical_mix,$signed(dut.pal_previous_line[8:0]),$signed(dut.pal_previous_line[18:10]),$signed(dut.output_cb),$signed(dut.output_cr),dut.center_addr,dut.pal_completed_line_length);
      if (compare_rgb && gray_check_enable && m<=8 &&
          (rgb_out[23:16]!==rgb_out[15:8] || rgb_out[15:8]!==rgb_out[7:0]))
        $fatal(1,"grayscale neutrality failure mode=%0d output=%06h",m,rgb_out);
      if (compare_rgb && m>=2 && m<=8) begin
        if ($signed(dut.r_result)<0 || $signed(dut.g_result)<0 || $signed(dut.b_result)<0)
          underflow_outputs=underflow_outputs+1;
        if ($signed(dut.r_result)>255 || $signed(dut.g_result)>255 || $signed(dut.b_result)>255)
          overflow_outputs=overflow_outputs+1;
      end
      last_hb=hb; last_vb=vb; last_hs=hs; last_vs=vs; last_dot=dotc;
      checks=checks+1;
    end
  endtask

  task automatic run_line(input [3:0] m,input integer width,input integer pal_valid,input integer intl,
                          input integer which);
    integer k,x,lo,hi;
    reg [23:0] e;
    begin
      gray_line_active=(which==1 || which==3 || which==10 || which==11 || which==12 || which==13);
      gray_check_enable=gray_line_active && (m<5 || !pal_valid || gray_previous_line);
      for(k=0;k<width;k=k+1) pixels[k]=scene(which,k,line_number);
      cycle(m,1,0,0,vsync_in,dotclk_in,intl,24'h000000,0,0);
      for(k=0;k<width;k=k+1) begin
        // Check the centered sample once the right-hand input tap arrives.
        if(k>0) begin
          x=k-1; e=expected_pixel(m,x,width,pal_valid,intl);
          if ((which==7 || which==8) && m>=2 && (m<=4 || m==7 || m==8) &&
              (m<=4 || !pal_valid || intl || x>=previous_width || sample(x,previous_width,1)==pixels[x]) && e!==pixels[x])
            $fatal(1,"constant-color identity failure mode=%0d color=%06h result=%06h",m,pixels[x],e);
          if (which==11 && m>=5 && pal_valid && !intl && e!==pixels[x])
            $fatal(1,"PAL blurred luma vertically mode=%0d current=%06h previous=%06h result=%06h",m,pixels[x],previous_line[x],e);
          cycle(m,0,0,k[0],vsync_in,k[0],intl,pixels[k],1,e);
          actual_luma[x]=(rgb_out[23:16]+2*rgb_out[15:8]+rgb_out[7:0])>>2;
          if (which==9) begin
            colored_dither[m][x]=rgb_out;
            if ((m==5 || m==6 || m==7 || m==8) && !pal_valid) repeated_pal_dither[m][x]=rgb_out;
            if ((m==7 || m==8) && width==24 && rgb_out!==repeated_pal_dither[m][x])
              $fatal(1,"PAL Strong changed same-row or interlaced chroma at x=%0d",x);
          end
          if (which==13) neutral_gray[m][x]=rgb_out;
          if ((m==7 || m==8) && which==2 && pal_valid && !intl &&
              rgb_out!==ycc_pixel(m,x,width,0,previous_width)) begin
            if(m==7) pal7_vertical_differences=pal7_vertical_differences+1;
            else pal8_vertical_differences=pal8_vertical_differences+1;
          end
        end else cycle(m,0,0,0,vsync_in,0,intl,pixels[k],0,0);
      end
      x=width-1; e=expected_pixel(m,x,width,pal_valid,intl);
      if ((which==7 || which==8) && m>=2 && (m<=4 || m==7 || m==8) &&
          (m<=4 || !pal_valid || intl || x>=previous_width || sample(x,previous_width,1)==pixels[x]) && e!==pixels[x])
        $fatal(1,"constant-color edge identity failure mode=%0d color=%06h result=%06h",m,pixels[x],e);
      if (which==11 && m>=5 && pal_valid && !intl && e!==pixels[x])
        $fatal(1,"PAL blurred luma vertically at edge mode=%0d current=%06h previous=%06h result=%06h",m,pixels[x],previous_line[x],e);
      cycle(m,1,0,1,vsync_in,1,intl,pixels[x],1,e); // flush final center, right edge clamps
      actual_luma[x]=(rgb_out[23:16]+2*rgb_out[15:8]+rgb_out[7:0])>>2;
      if (which==9) begin
        colored_dither[m][x]=rgb_out;
        if ((m==5 || m==6 || m==7 || m==8) && !pal_valid) repeated_pal_dither[m][x]=rgb_out;
        if ((m==7 || m==8) && width==24 && rgb_out!==repeated_pal_dither[m][x])
          $fatal(1,"PAL Strong changed repeated/interlaced right edge");
      end
      if (which==13) neutral_gray[m][x]=rgb_out;
      if ((m==7 || m==8) && which==2 && pal_valid && !intl &&
          rgb_out!==ycc_pixel(m,x,width,0,previous_width)) begin
        if(m==7) pal7_vertical_differences=pal7_vertical_differences+1;
        else pal8_vertical_differences=pal8_vertical_differences+1;
      end
      cycle(m,1,0,0,vsync_in,0,intl,24'hffffff,0,0);
      cycle(m,1,0,0,vsync_in,1,intl,24'h000000,0,0);
      for(k=0;k<width;k=k+1) previous_line[k]=pixels[k];
      if ((which==10 || which==12) && m>=2 && m<=4) begin
        lo=1000; hi=-1;
        for(k=4;k<width-4;k=k+1) begin
          if(actual_luma[k]<lo) lo=actual_luma[k];
          if(actual_luma[k]>hi) hi=actual_luma[k];
        end
        if (which==12 && (hi-lo)!=(m==2?128:m==3?64:32))
          $fatal(1,"actual one-pixel luma contrast mode=%0d expected=%0d got=%0d",m,(m==2?128:m==3?64:0),hi-lo);
        if (which==10 && (hi-lo)!=(m==2?192:m==3?96:48))
          $fatal(1,"actual two-pixel luma contrast mode=%0d expected=%0d got=%0d",m,(m==2?192:m==3?96:0),hi-lo);
        $display("ACTUAL mode %0d scene %0d luma p-p=%0d",m,which,hi-lo);
      end
      gray_previous_line=gray_line_active;
      previous_width=width;
      line_number=line_number+1;
    end
  endtask

  integer m,p;
  initial begin
    for(p=0;p<521;p=p+1) begin pixels[p]=0; previous_line[p]=0; end
    // Start a frame and exercise all NTSC strengths over each scene.
    cycle(0,1,1,0,0,0,0,0,0,0);
    cycle(0,1,1,0,1,0,0,0,0,0);
    cycle(0,1,0,0,0,0,0,0,0,0);
    for(p=0;p<7;p=p+1) begin
      run_line(2,24,0,0,p);
      run_line(3,24,0,0,p);
      run_line(4,24,0,0,p);
    end
    for(p=7;p<=10;p=p+1) begin
      run_line(2,24,0,0,p);
      run_line(3,24,0,0,p);
      run_line(4,24,0,0,p);
    end
    for(p=12;p<=12;p=p+1) begin
      run_line(2,24,0,0,p);
      run_line(3,24,0,0,p);
      run_line(4,24,0,0,p);
    end
    for(p=13;p<=13;p=p+1) begin
      run_line(2,24,0,0,p);
      run_line(3,24,0,0,p);
      run_line(4,24,0,0,p);
    end
    // PAL previous-line chroma blend, changed line width, interlace bypass,
    // and mode-change invalidation. Include both PAL strengths.
    run_line(5,24,0,0,6);
    run_line(5,16,1,0,2);
    run_line(5,24,1,0,3);
    run_line(5,24,1,1,4);
    run_line(6,24,0,0,5);
    run_line(6,24,1,0,1);
    // Mode changes during blanking discard prior-line history, then a second
    // line in the selected mode can blend normally.
    run_line(5,24,0,0,6); // mode changed from PAL 6; first line is horizontal-only
    run_line(6,24,0,0,3); // mode changed again; first line is horizontal-only
    run_line(6,24,1,0,2);
    // Contrasting monochrome PAL rows prove only chroma is blended vertically.
    run_line(5,24,0,0,11);
    run_line(5,24,1,0,11);
    run_line(7,24,0,0,11);
    run_line(7,24,1,0,11);
    run_line(5,24,1,0,13);
    run_line(5,24,1,0,13);
    run_line(6,24,0,0,13);
    run_line(6,24,1,0,13);
    run_line(4,24,0,0,13);
    run_line(7,24,0,0,13);
    run_line(7,24,1,0,13);
    run_line(8,24,0,0,13);
    run_line(8,24,1,0,13);
    // Matching neutral rows must agree between their NTSC and PAL luma modes.
    run_line(2,24,0,0,13);
    run_line(5,24,0,0,13);
    run_line(5,24,1,0,13);
    run_line(3,24,0,0,13);
    run_line(6,24,0,0,13);
    run_line(6,24,1,0,13);
    // Colored 2-on/2-off rows repeat vertically. Any PAL/NTSC difference
    // therefore comes from the selected horizontal chroma kernel only.
    run_line(2,24,0,0,9);
    run_line(3,24,0,0,9);
    run_line(5,24,0,0,9);
    run_line(5,24,1,0,9);
    run_line(4,24,0,0,9);
    run_line(6,24,0,0,9);
    run_line(6,24,1,0,9);
    begin : check_pal_chroma_mapping
      integer x,diff_pal1,diff_pal2;
      diff_pal1=0; diff_pal2=0;
      for(x=0;x<24;x=x+1) begin
        if(colored_dither[5][x]!==repeated_pal_dither[5][x])
          $fatal(1,"PAL1 repeated row changed output despite equal chroma at x=%0d",x);
        if(colored_dither[6][x]!==repeated_pal_dither[6][x])
          $fatal(1,"PAL2 repeated row changed output despite equal chroma at x=%0d",x);
        if(colored_dither[5][x]!==colored_dither[2][x]) diff_pal1=diff_pal1+1;
        if(colored_dither[6][x]!==colored_dither[3][x]) diff_pal2=diff_pal2+1;
        if(neutral_gray[5][x]!==neutral_gray[2][x])
          $fatal(1,"neutral PAL1 differs from NTSC1 at x=%0d",x);
        if(neutral_gray[6][x]!==neutral_gray[3][x])
          $fatal(1,"neutral PAL2 differs from NTSC2 at x=%0d",x);
        if(neutral_gray[7][x]!==neutral_gray[4][x])
          $fatal(1,"neutral PAL Strong differs from NTSC Strong at x=%0d",x);
        if(neutral_gray[8][x]!==neutral_gray[7][x])
          $fatal(1,"PAL Strong+ changed luma on a neutral row at x=%0d",x);
      end
      if(diff_pal1==0 || diff_pal2==0)
        $fatal(1,"PAL chroma modes not distinguishable from NTSC neighbors: PAL1=%0d PAL2=%0d",diff_pal1,diff_pal2);
      $display("PASS: PAL1 differs from NTSC1 at %0d pixels; PAL2 differs from NTSC2 at %0d pixels; neutral pairs match",diff_pal1,diff_pal2);
    end
    // PAL Strong retains full-box chroma and stronger-than-Medium luma; a
    // different prior row also exercises its configured vertical chroma blend.
    run_line(7,24,0,0,9);
    run_line(7,24,1,0,9);
    pal7_vertical_differences=0;
    run_line(7,24,1,0,2);
    if(pal7_vertical_differences==0)
      $fatal(1,"PAL Strong did not show vertical chroma influence for a changed row");
    $display("PASS: PAL Strong vertical chroma differs from horizontal-only at %0d samples",pal7_vertical_differences);
    run_line(7,24,1,1,9);
    // PAL Strong+ keeps mode 7's horizontal box chroma and uses a 5:3 vertical
    // chroma ratio. The signed reference model checks every output sample.
    run_line(8,24,0,0,9);
    run_line(8,24,1,0,9);
    pal8_vertical_differences=0;
    run_line(8,24,1,0,2);
    if(pal8_vertical_differences==0)
      $fatal(1,"PAL Strong+ did not show 5:3 vertical chroma influence");
    run_line(8,24,1,1,9);
    run_line(8,24,1,1,11); // seed neutral chroma while bypassing the colored prior row
    run_line(8,24,1,0,11);
    // Every base scene in Strong+: solids, saturated bars, checker/dither,
    // arbitrary RGB, and alternating prior rows with signed chroma extremes.
    for(p=0;p<=8;p=p+1) begin
      run_line(7,24,0,0,p);
      run_line(8,24,0,0,p);
      run_line(8,24,1,0,p);
    end
    // Switching between PAL strengths invalidates line history both ways.
    run_line(7,24,0,0,9);
    run_line(8,24,0,0,9);
    run_line(8,24,1,0,9);
    // Mode changes invalidate PAL history. Check solid round-trip and
    // saturation behavior in PAL Strong before continuing with short lines.
    run_line(4,24,0,0,5);
    run_line(7,24,0,0,8);
    run_line(7,24,1,0,8);
    run_line(7,24,1,0,5);
    // A frame boundary clears history. Short lines cover endpoint clamping.
    cycle(0,1,1,0,0,0,0,0,0,0);
    cycle(0,1,1,0,1,0,0,0,0,0);
    cycle(0,1,0,0,0,0,0,0,0,0);
    previous_width=0;
    run_line(5,3,0,0,2);
    run_line(5,3,1,0,5);
    run_line(5,1,1,0,1);
    run_line(7,3,0,0,9);
    run_line(7,3,1,0,9);
    run_line(7,1,1,0,8);
    run_line(8,3,0,0,9);
    run_line(8,3,1,0,9);
    run_line(8,1,1,0,8);
    // Exercise the 512-entry PAL line store and the first unsupported sample.
    run_line(5,512,0,0,2);
    run_line(5,513,1,0,3);
    run_line(7,512,0,0,9);
    run_line(7,513,1,0,5);
    run_line(8,512,0,0,9);
    run_line(8,513,1,0,5);
    // Keep Off and Full paths covered for alignment and regression.
    run_line(0,24,0,0,3);
    run_line(1,24,0,0,1);
    if (underflow_outputs==0 || overflow_outputs==0)
      $fatal(1,"clipping coverage missing: underflow=%0d overflow=%0d",underflow_outputs,overflow_outputs);
    $display("PASS: %0d checks, clipping underflow=%0d overflow=%0d",checks,underflow_outputs,overflow_outputs);
    $finish;
  end
endmodule
