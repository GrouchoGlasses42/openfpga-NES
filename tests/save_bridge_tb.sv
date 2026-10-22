`timescale 1ns/1ps
module save_bridge_tb;
  reg clk_74a=0,clk_85_9=0,clk_ppu_21_47=0;
  always #6.734 clk_74a=~clk_74a;
  always #5.82 clk_85_9=~clk_85_9;
  always #23.28 clk_ppu_21_47=~clk_ppu_21_47;
  reg bridge_wr=0,bridge_rd=0;
  reg [31:0] bridge_addr=0,bridge_wr_data=0;
  wire [31:0] sd_read_data;
  wire sd_buff_wr,sd_buff_rd,save_wr,save_rd,save_busy;
  wire [18:0] sd_buff_addr;
  wire [7:0] sd_buff_dout,sd_buff_din;
  reg requestread=0,requestwrite=0,allcomplete=1;
  reg [15:0] requestread_id=0,requestwrite_id=0;
  wire transfer_active,transfer_loading,read_ack,write_ack;
  wire memory_owned,memory_ready,ppu_memory_read,cpu_memory_read;
  reg loader_busy=0,corepaused=0;
  integer pause_ticks=0;
`ifdef GUARDED_TRANSFER
  save_transfer_controller transfer(
    .clk_74a(clk_74a),.clk_ppu_21_47(clk_ppu_21_47),.clock_locked(1'b1),
    .requestread(requestread),.requestwrite(requestwrite),
    .requestread_id(requestread_id),.requestwrite_id(requestwrite_id),
    .allcomplete(allcomplete),.memory_ready(memory_ready),
    .requestread_ack(read_ack),.requestwrite_ack(write_ack),
    .active(transfer_active),.loading(transfer_loading));
  // A read must wait for a later safe video/CPU boundary, rather than assuming
  // that requesting a pause instantly stops the CPU and PPU.
  always @(posedge clk_ppu_21_47) begin
    if(transfer_active && !transfer_loading) begin
      if(pause_ticks<20000) pause_ticks<=pause_ticks+1;
      else corepaused<=1;
    end else begin corepaused<=0;pause_ticks<=0;end
  end
  always @(posedge clk_74a) begin
    if((read_ack && requestread_id==10)||(write_ack && requestwrite_id==10))
      if(!memory_owned || !memory_ready || loader_busy)
        $fatal(1,"Persistent transfer acknowledged before memory was reserved");
  end
`else
  assign transfer_active=0,transfer_loading=0,read_ack=1,write_ack=1;
`endif
  save_bridge_ports ports(.clk_74a(clk_74a),.clk_85_9(clk_85_9),.clk_ppu_21_47(clk_ppu_21_47),
    .bridge_wr(bridge_wr),.bridge_rd(bridge_rd),.bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data),.bridge_endian_little(1'b0),
    .sd_read_data(sd_read_data),.sd_buff_wr(sd_buff_wr),.sd_buff_rd(sd_buff_rd),
    .sd_buff_addr(sd_buff_addr),.sd_buff_dout(sd_buff_dout),.sd_buff_din(sd_buff_din),
    .save_busy(save_busy),.save_wr(save_wr),.save_rd(save_rd),
    .save_transfer_active(transfer_active),.save_transfer_loading(transfer_loading),
    .downloading(1'b0),.loader_busy(loader_busy),.clearing_ram(1'b0),
    .sleep_savestate(1'b0),.corepaused(corepaused),
    .save_memory_owned(memory_owned),.save_memory_ready(memory_ready),
    .ppu_read(ppu_traffic),.cpu_read(cpu_read|cpu_traffic),
    .ppu_memory_read(ppu_memory_read),.cpu_memory_read(cpu_memory_read));
  wire [15:0] dq;
  wire [12:0] address;
  wire [1:0] bank;
  wire dqml,dqmh,csn,wen,rasn,casn,sdram_clk;
  reg cpu_read=0,restore_cache=0;
  reg competing=0;
  reg [7:0] traffic_cycle=0;
  always @(posedge clk_85_9) traffic_cycle<=traffic_cycle+1;
  wire ppu_traffic=competing && traffic_cycle[3:0]<4;
  wire cpu_traffic=competing && traffic_cycle[5:0]>=8 && traffic_cycle[5:0]<12;
  wire [7:0] cpu_data;
  reg [5:0] refresh_counter=0;
  always @(posedge clk_85_9) refresh_counter<=refresh_counter+1;
  sdram memory(.clk(clk_85_9),.init(1'b0),
    .ch0_addr(25'h200000+{17'b0,traffic_cycle}),.ch0_rd(ppu_memory_read),.ch0_wr(1'b0),.ch0_din(8'b0),.ch0_dout(),.ch0_busy(),
    .ch1_addr(cpu_traffic ? 25'h300000+{17'b0,traffic_cycle} : 25'h3c0000),.ch1_rd(cpu_memory_read),.ch1_wr(1'b0),.ch1_din(8'b0),.ch1_dout(cpu_data),.ch1_busy(),
    .ch2_addr({7'b0001111,sd_buff_addr[17:0]}),.ch2_rd(save_rd),.ch2_wr(save_wr),
    .ch2_din(sd_buff_dout),.ch2_dout(sd_buff_din),.ch2_busy(save_busy),
    .refresh(refresh_counter==0 || memory_owned),.ss_in(16'b0),.ss_load(restore_cache),.ss_out(),
    .SDRAM_DQ_in(dq_data),.SDRAM_DQ_out(dq),.SDRAM_A(address),.SDRAM_DQML(dqml),.SDRAM_DQMH(dqmh),
    .SDRAM_BA(bank),.SDRAM_nCS(csn),.SDRAM_nWE(wen),.SDRAM_nRAS(rasn),
    .SDRAM_nCAS(casn),.SDRAM_CLK(sdram_clk),.SDRAM_CKE());
  // Behavioral SDRAM pin model: ACTIVATE row, READ CAS=2, byte-masked WRITE.
  reg [15:0] ram[0:131071];
  reg [12:0] rows[0:3];
  reg drive=0;
  reg [15:0] dq_data=0;
  integer latency=0,read_index=0;
  wire [23:0] index_full={bank,address[8:0],rows[bank]};
  wire [16:0] index_now=index_full[16:0];
  always @(negedge clk_85_9) begin
    drive<=0;
    if(latency>0) begin
      latency<=latency-1;
      if(latency==1) begin dq_data<=ram[read_index]; drive<=1; end
    end
    case({rasn,casn,wen})
      3'b011: rows[bank]<=address;
      3'b101: begin read_index<=index_now; latency<=2; end
      3'b100: begin
        if(!dqml) ram[index_now][7:0]<=dq[7:0];
        if(!dqmh) ram[index_now][15:8]<=dq[15:8];
      end
    endcase
  end
  reg [7:0] image[0:262143];
  reg use_image=0;
  string image_path;
  function automatic [7:0] pattern(input integer offset);
    pattern=use_image ? image[offset] : offset[7:0]^offset[15:8]^offset[23:16]^8'ha7;
  endfunction
  function automatic [31:0] word_at(input integer offset);
    word_at={pattern(offset),pattern(offset+1),pattern(offset+2),pattern(offset+3)};
  endfunction
  always @(posedge clk_74a) begin
    if(ports.save_data_loader.dcfifo_component.impl.overflow_count) begin
      if($test$plusargs("legacy")) begin
        $display("REPRODUCED: released save-file loader overflows at the documented 88-clock bridge cadence");
        $finish;
      end else $fatal(1,"Save-file write FIFO overflow");
    end
    if(ports.save_data_unloader.fifo_address_req.impl.overflow_count ||
       ports.save_data_unloader.fifo_data_response.impl.overflow_count)
      $fatal(1,"Save-file read FIFO overflow");
  end
  integer n;
  task automatic start_transfer(input bit writing);
`ifdef GUARDED_TRANSFER
    @(negedge clk_74a);
    allcomplete=0;
    if(writing) begin requestwrite=1;requestwrite_id=10;end
    else begin requestread=1;requestread_id=10;end
    // ACK must wait through CDC, drain, and (on reads) the safe pause point.
    if(writing ? write_ack : read_ack) $fatal(1,"Immediate save ACK");
    do @(negedge clk_74a); while(!(writing ? write_ack : read_ack));
    if(writing && !transfer_loading) $fatal(1,"Wrong save-transfer direction");
    if(!writing && !corepaused) $fatal(1,"Read started before safe pause");
    requestread=0;requestwrite=0;
`endif
  endtask
  task automatic finish_transfer;
`ifdef GUARDED_TRANSFER
    @(negedge clk_74a);allcomplete=1;
    wait(!transfer_active);
`endif
  endtask
  integer debug_cycles=0;
  always @(posedge clk_85_9) if($test$plusargs("debug") && bridge_addr==32'h20000000 && !bridge_wr) begin
    if(debug_cycles<110 && $time>77000000) begin
      $display("DBG t=%t rd=%b addr=%h state=%d cmd=%b out=%h dq=%h fifo=%h",$time,save_rd,sd_buff_addr,memory.state,{rasn,casn,wen},sd_buff_din,dq_data,sd_read_data);
      debug_cycles<=debug_cycles+1;
    end
  end
  initial begin
    use_image=$value$plusargs("image=%s",image_path);
    if(use_image) $readmemh(image_path,image);
    for(n=0;n<131072;n=n+1) ram[n]=0;
    repeat(400) @(negedge clk_74a);
`ifdef GUARDED_TRANSFER
    competing=1;
    loader_busy=1;
    fork
      begin repeat(100000) @(negedge clk_85_9);loader_busy=0;end
      begin start_transfer(1); end
    join
`endif
    for(n=0;n<262144;n=n+4) begin
      bridge_addr=32'h20000000+n; bridge_wr_data=word_at(n); bridge_wr=1;
      @(negedge clk_74a); bridge_wr=0;
      repeat(87) @(negedge clk_74a);
    end
    repeat(100) @(negedge clk_74a);
    finish_transfer();
    for(n=0;n<262144;n=n+1) begin
      if((n&1 ? ram[n/2][15:8] : ram[n/2][7:0])!==pattern(n))
        $fatal(1,"Saved disk reload corrupted at byte %h",n);
    end
    competing=$test$plusargs("contention") || $test$plusargs("guarded");
    start_transfer(0);
    for(n=0;n<262144;n=n+4) begin
      bridge_addr=32'h20000000+n; bridge_rd=1;
      @(negedge clk_74a); bridge_rd=0;
      repeat(87) @(negedge clk_74a);
      if(sd_read_data!==word_at(n)) $fatal(1,"Save-file read %h: %h expected %h",n,sd_read_data,word_at(n));
    end
    competing=0;
    finish_transfer();
    $display("PASS: complete 256 KiB disk-save reload/readback through actual SDRAM controller and extracted bridge instances");
    @(negedge clk_85_9); cpu_read=1;
    repeat(20) @(negedge clk_85_9); cpu_read=0;
    repeat(10) @(negedge clk_85_9);
    if(cpu_data!==pattern(0)) $fatal(1,"Initial CPU cached read failed");
    start_transfer(1);
    @(negedge clk_74a); bridge_addr=32'h20000000;bridge_wr_data=32'h11223344;bridge_wr=1;
    @(negedge clk_74a);bridge_wr=0;
    repeat(100) @(negedge clk_74a);
    finish_transfer();
    @(negedge clk_85_9);cpu_read=1;
    repeat(20) @(negedge clk_85_9);cpu_read=0;
    repeat(10) @(negedge clk_85_9);
    if(cpu_data!==8'h11) $fatal(1,"CPU cache survived disk-save write");
    ram[0]=16'h6677;
    restore_cache=1; @(negedge clk_85_9);restore_cache=0;cpu_read=1;
    repeat(20) @(negedge clk_85_9);cpu_read=0;
    repeat(10) @(negedge clk_85_9);
    if(cpu_data!==8'h77) $fatal(1,"CPU cache survived state restore");
    $display("PASS: CPU cached words invalidated on save-file writes and state restore");
    $finish;
  end
  initial begin repeat(500) #1ms; $fatal(1,"Save-file bridge timed out"); end
endmodule
