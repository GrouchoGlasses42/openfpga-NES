`timescale 1ns/1ps
module state_stream_tb;
  reg clk_74a=0, clk_85_9=0, clk_ppu_21_47=0;
  always #6.734 clk_74a=~clk_74a;
  always #5.82 clk_85_9=~clk_85_9;
  always #23.28 clk_ppu_21_47=~clk_ppu_21_47;
  reg bridge_wr=0, bridge_rd=0;
  reg [31:0] bridge_addr=0, bridge_wr_data=0;
  wire [31:0] bridge_data;
  reg start=0, load=0;
  wire start_ack,start_busy,start_ok,start_err,load_ack,load_busy,load_ok,load_err;
  wire ss_save,ss_load,ss_ack,ss_busy,ss_req,ss_rnw;
  wire [63:0] ss_to_bridge,ss_from_bridge;
  wire [25:0] ss_addr;
  wire [7:0] ss_be;
  save_state_controller adapter(.clk_74a(clk_74a),.clk_mem_85_9(clk_85_9),
    .clk_ppu_21_47(clk_ppu_21_47),.bridge_wr(bridge_wr),.bridge_rd(bridge_rd),
    .bridge_endian_little(1'b0),.bridge_addr(bridge_addr),.bridge_wr_data(bridge_wr_data),
    .save_state_bridge_read_data(bridge_data),.savestate_start(start),
    .savestate_start_ack_s(start_ack),.savestate_start_busy_s(start_busy),
    .savestate_start_ok_s(start_ok),.savestate_start_err_s(start_err),
    .savestate_load(load),.savestate_load_ack_s(load_ack),.savestate_load_busy_s(load_busy),
    .savestate_load_ok_s(load_ok),.savestate_load_err_s(load_err),
    .ss_save(ss_save),.ss_load(ss_load),.ss_din(ss_to_bridge),.ss_dout(ss_from_bridge),
    .ss_addr(ss_addr),.ss_rnw(ss_rnw),.ss_req(ss_req),.ss_be(ss_be),.ss_ack(ss_ack),.ss_busy(ss_busy)
`ifdef STATE_DONE_CHECK
    ,.ss_load_done(done)
`endif
  );
  wire [63:0] state_din;
  wire [9:0] state_addr;
  wire state_wren,state_reset,sleeping,loading,saving,done;
  wire [24:0] mem_addr;
  wire [2:0] mem_type;
  wire mem_read,mem_write;
  wire [7:0] mem_data;
  function automatic [7:0] pattern(input [2:0] kind,input [24:0] addr);
    pattern = addr[7:0] ^ addr[15:8] ^ addr[23:16] ^ (kind*37);
  endfunction
  function automatic [63:0] internal_word(input [9:0] address);
    internal_word=64'h12345678aabbccdd ^ (64'h0102030405060708*address);
  endfunction
  wire [7:0] sdram_data;
  wire [7:0] memory_data=mem_type>1 ? sdram_data : pattern(mem_type,mem_addr);
  wire [15:0] ram_in,ram_out;
  wire [12:0] ram_address;
  wire [1:0] ram_bank;
  wire ram_rasn,ram_casn,ram_wen,ram_dqml,ram_dqmh;
  sdram physical(.clk(clk_85_9),.init(1'b0),
    .ch0_addr(25'b0),.ch0_rd(1'b0),.ch0_wr(1'b0),.ch0_din(8'b0),.ch0_dout(),.ch0_busy(),
    .ch1_addr(25'b0),.ch1_rd(1'b0),.ch1_wr(1'b0),.ch1_din(8'b0),.ch1_dout(),.ch1_busy(),
    .ch2_addr(mem_addr),.ch2_rd(mem_read && mem_type>1),.ch2_wr(mem_write && mem_type>1),
    .ch2_din(mem_data),.ch2_dout(sdram_data),.ch2_busy(),
    .refresh(1'b1),.ss_in(16'b0),.ss_load(loading),.ss_out(),
    .SDRAM_DQ_in(ram_out),.SDRAM_DQ_out(ram_in),.SDRAM_A(ram_address),
    .SDRAM_DQML(ram_dqml),.SDRAM_DQMH(ram_dqmh),.SDRAM_BA(ram_bank),
    .SDRAM_nCS(),.SDRAM_nWE(ram_wen),.SDRAM_nRAS(ram_rasn),.SDRAM_nCAS(ram_casn),
    .SDRAM_CLK(),.SDRAM_CKE());
  sdram_pin_model pins(.clk(clk_85_9),.address(ram_address),.bank(ram_bank),
    .rasn(ram_rasn),.casn(ram_casn),.wen(ram_wen),.dqml(ram_dqml),.dqmh(ram_dqmh),
    .data_in(ram_in),.data_out(ram_out));
  savestates engine(.clk(clk_ppu_21_47),.reset_in(1'b0),.reset_ss(),.reset_delay(),
    .load_done(done),.increaseSSHeaderCount(1'b1),.save(ss_save),.load(ss_load),
    .savestate_address(0),.savestate_busy(ss_busy),.paused(sleeping),
    .BUS_Din(state_din),.BUS_Adr(state_addr),.BUS_wren(state_wren),.BUS_rst(state_reset),
    .BUS_Dout(internal_word(state_addr)),.loading_savestate(loading),
    .saving_savestate(saving),.sleep_savestate(sleeping),
    .Save_RAMAddr(mem_addr),.Save_RAMRdEn(mem_read),.Save_RAMWrEn(mem_write),
    .Save_RAMWriteData(mem_data),.Save_RAMReadData(memory_data),.Save_RAMType(mem_type),
    .bus_out_Din(ss_to_bridge),.bus_out_Dout(ss_from_bridge),.bus_out_Adr(ss_addr),
    .bus_out_rnw(ss_rnw),.bus_out_ena(ss_req),.bus_out_be(ss_be),.bus_out_done(ss_ack));
  integer writes[0:5]='{default:0}, internals=0;
  reg previous_write=0;
  always @(posedge clk_ppu_21_47) begin
    previous_write<=mem_write;
    if(mem_write && !previous_write) begin
      if(mem_data!==pattern(mem_type,mem_addr))
        $fatal(1,"Restored RAM type %0d address %h: %h expected %h",mem_type,mem_addr,mem_data,pattern(mem_type,mem_addr));
      writes[mem_type]<=writes[mem_type]+1;
    end
    if(state_wren) begin
      if(state_din!==internal_word(state_addr)) $fatal(1,"Internal state %0d corrupt",state_addr);
      internals<=internals+1;
    end
    if(adapter.fifo_load.overflow_count) $fatal(1,"State upload FIFO overflow");
  end
  localparam BYTES=32'h143308;
  reg [31:0] image[0:BYTES/4-1];
  function automatic [31:0] swap32(input [31:0] value);
    swap32={value[7:0],value[15:8],value[23:16],value[31:24]};
  endfunction
  integer sizes[0:5]='{256,8192,1048576,2048,2048,262144};
  integer offsets[0:5]='{0,0,32'h200000,32'h3a0000,32'h380000,32'h3c0000};
  integer n,round,kind,addr;
  initial begin
    for(kind=2;kind<6;kind=kind+1)
      for(n=0;n<sizes[kind];n=n+2) begin
        addr=offsets[kind]+n;
        pins.ram[addr/2]={pattern(kind,addr+1),pattern(kind,addr)};
      end
    repeat(20) @(negedge clk_74a);
    for(round=0;round<2;round=round+1) begin
      start=1; wait(start_ack); @(negedge clk_74a); start=0;
      wait(start_ok); repeat(10) @(negedge clk_74a);
      for(n=0;n<BYTES/4;n=n+1) begin
        bridge_addr=32'h40000000+n*4; bridge_rd=1;
        @(negedge clk_74a); bridge_rd=0;
        repeat(87) @(negedge clk_74a);
        image[n]=bridge_data;
        if(n==1 && $test$plusargs("legacy") && swap32(image[1])!==331776) begin
          $display("REPRODUCED: original state stream starts with internal registers instead of its header (%h)",swap32(image[1]));
          $finish;
        end
      end
      if(swap32(image[1])!==330944) begin
        if($test$plusargs("legacy")) begin
          $display("REPRODUCED: original state stream does not start with its header (%h)",swap32(image[1]));
          $finish;
        end
        $fatal(1,"State header/length mismatch: %h",swap32(image[1]));
      end
      wait(!ss_busy); repeat(40) @(negedge clk_74a);
      for(kind=2;kind<6;kind=kind+1)
        for(n=0;n<sizes[kind];n=n+2) pins.ram[(offsets[kind]+n)/2]=16'hdead;
      for(n=0;n<BYTES/4;n=n+1) begin
        bridge_addr=32'h40000000+n*4; bridge_wr_data=image[n]; bridge_wr=1;
        @(negedge clk_74a); bridge_wr=0;
        repeat(87) @(negedge clk_74a);
      end
      load=1; wait(load_ack); @(negedge clk_74a); load=0;
      wait(load_ok); repeat(40) @(negedge clk_74a);
      if(internals!=(round+1)*64) $fatal(1,"Wrong internal count %0d",internals);
      for(n=0;n<6;n=n+1) if(writes[n]!=(round+1)*sizes[n])
        $fatal(1,"RAM region %0d wrote %0d bytes",n,writes[n]);
      for(kind=2;kind<6;kind=kind+1)
        for(n=0;n<sizes[kind];n=n+2) begin
          addr=offsets[kind]+n;
          if(pins.ram[addr/2]!=={pattern(kind,addr+1),pattern(kind,addr)})
            $fatal(1,"SDRAM restoration failed at %h",addr);
        end
      $display("PASS: full state round %0d, 64 internal registers and all six memory regions",round+1);
    end
    $display("PASS: two complete Pocket bridge state round trips at 88 bridge clocks/word, no FIFO overflow");
`ifdef STATE_DONE_CHECK
    for(n=0;n<2;n=n+1) begin
      bridge_addr=32'h40000000+n*4;bridge_wr_data=0;bridge_wr=1;
      @(negedge clk_74a);bridge_wr=0;
      repeat(87) @(negedge clk_74a);
    end
    load=1;wait(load_ack);@(negedge clk_74a);load=0;
    wait(load_err);
    if(load_ok || internals!=128) $fatal(1,"Invalid state reported success or modified registers");
    $display("PASS: invalid state header reports a Pocket load error without modifying registers");
`endif
    $finish;
  end
  initial begin repeat(3000) #1ms; $fatal(1,"State transfer timed out"); end
endmodule
