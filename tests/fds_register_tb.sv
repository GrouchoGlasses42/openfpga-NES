`timescale 1ns/1ps
// Bus-level reproduction of the three FDS-Mirroring-Test register sequences.
module fds_register_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg ce=0, enable=0, wr=0, rd=0;
  reg [15:0] address=0;
  reg [13:0] ppu_address=0;
  reg [7:0] data=0;
  reg [63:0] state_data=0;
  reg [9:0] state_address=0;
  reg state_write=0, state_load=0;
  wire [63:0] state_out;
  tri [7:0] result;
  tri [21:0] chr_addr;
  tri mirror, vram_enable;
  MapperFDS dut(
    .clk(clk),.ce(ce),.enable(enable),.flags(32'b0),
    .prg_ain(address),.prg_aout_b(),.prg_read(rd),.prg_write(wr),
    .prg_din(data),.prg_dout_b(result),.prg_allow_b(),
    .chr_ain(ppu_address),.chr_aout_b(chr_addr),.chr_read(1'b0),.chr_allow_b(),
    .vram_a10_b(mirror),.vram_ce_b(vram_enable),.irq_b(),
    .audio_in(16'b0),.audio_b(),.flags_out_b(),.prg_dbus(8'b0),.audio_dout(8'b0),
    .diskside_b(),.max_diskside(2'b0),.fds_busy(1'b0),.fds_eject_btn(1'b0),
    .fds_auto_eject_en(1'b0),.fds_fast(1'b0),
    .SaveStateBus_Din(state_data),.SaveStateBus_Adr(state_address),
    .SaveStateBus_wren(state_write),.SaveStateBus_rst(1'b0),
    .SaveStateBus_load(state_load),.SaveStateBus_Dout(state_out)
  );
  reg [7:0] vram [0:2047];
  integer first_fail=0, second_fail=0, third_fail=0, extra_fail=0;
  integer i,j;
  integer map_a,map_b;
  reg [63:0] saved;
  reg [7:0] status_before;

  task write_reg(input [15:0] a,input [7:0] v);
    @(negedge clk);ce=1;wr=1;address=a;data=v;
    @(negedge clk);ce=0;wr=0;
    repeat(2) @(negedge clk);
  endtask

  task check_pair(input [13:0] a,b,output integer failures);
    begin
      failures=0;
      ppu_address=a;#1;map_a={mirror,ppu_address[9:0]};
      if (!vram_enable) failures=failures+1;
      vram[map_a]=8'h55;vram[map_a+1]=8'haa;
      ppu_address=b;#1;map_b={mirror,ppu_address[9:0]};
      if(vram[map_b]!==8'h55 || vram[map_b+1]!==8'haa) failures=failures+1;
      vram[map_b]=8'haa;
      if(vram[map_a]!==8'haa) failures=failures+1;
    end
  endtask

  task check_status(input bit expected,output integer failures);
    begin
      address=16'h4030;#1;
      failures=(result[3]!==expected);
    end
  endtask

  initial begin
    for(i=0;i<2048;i=i+1)vram[i]=0;
    repeat(5)@(negedge clk);enable=1;
    write_reg(16'h4023,8'h83);
    write_reg(16'h4025,8'h08);
    check_pair(14'h2000,14'h2400,j);first_fail+=j;
    check_pair(14'h2800,14'h2c00,j);first_fail+=j;
    write_reg(16'h4025,8'h00);
    check_pair(14'h2000,14'h2800,j);first_fail+=j;
    check_pair(14'h2400,14'h2c00,j);first_fail+=j;
    write_reg(16'h4025,8'h08);check_status(1,j);second_fail+=j;
    write_reg(16'h4025,8'h00);check_status(0,j);second_fail+=j;
    write_reg(16'h4025,8'h08);
    write_reg(16'h4023,8'h82);check_status(0,j);third_fail+=j;
    write_reg(16'h4023,8'h83);check_status(0,j);third_fail+=j;
    check_pair(14'h2000,14'h2800,j);third_fail+=j;
    $display("MIRRORING: $4025 write=%s $4030 read=%s $4023 reset=%s",
             first_fail==0?"PASS":"FAIL",second_fail==0?"PASS":"FAIL",third_fail==0?"PASS":"FAIL");
    if($test$plusargs("baseline")) begin
      if(first_fail!=0 || second_fail==0 || third_fail==0)
        $fatal(1,"Baseline did not reproduce Pocket PASS/FAIL/FAIL");
      $display("PASS: baseline reproduces all three Pocket observations");
      $finish;
    end else begin
    if(first_fail || second_fail || third_fail)$fatal(1,"FDS mirroring register regression");
    // Disabled disk I/O must hold $4025 at $06 even if software writes it.
    write_reg(16'h4025,8'hff);
    write_reg(16'h4023,8'h82);
    write_reg(16'h4025,8'hff);
    check_status(0,j);extra_fail+=j;
    if ({dut.disk_irq_en,dut.byte_transfer,1'b0,1'b0,!dut.vertical,!dut.write_en,dut.diskreset,dut.motor_on}
        !==8'h06)extra_fail++;
    // Status remains readable; enabling I/O must not revive the old mirror.
    write_reg(16'h4023,8'h83);check_status(0,j);extra_fail+=j;
    // Restore the existing mapper state bit, with no layout expansion.
    write_reg(16'h4025,8'h08);
    state_address=32;#1;saved=state_out;
    write_reg(16'h4023,8'h82);check_status(0,j);extra_fail+=j;
    @(negedge clk);state_data=saved;state_write=1;
    @(negedge clk);state_write=0;state_load=1;
    @(negedge clk);state_load=0;
    check_status(1,j);extra_fail+=j;
    check_pair(14'h2000,14'h2400,j);extra_fail+=j;
    // Reads of the status bit cannot change it, and CE gates register writes.
    address=16'h4030;#1;status_before=result;
    repeat(4) begin
      @(negedge clk);rd=1;ce=1;
      @(negedge clk);rd=0;ce=0;
    end
    check_status(1,j);extra_fail+=j;
    @(negedge clk);address=16'h4025;data=0;wr=1;ce=0;
    repeat(3)@(negedge clk);
    wr=0;check_status(1,j);extra_fail+=j;
    if(extra_fail)$fatal(1,"FDS reset/write-gating/state regression count=%0d",extra_fail);
    $display("PASS: mirror readback, disabled-I/O reset/write gating, readable status, CE and state restore");
    $finish;
    end
  end
endmodule
