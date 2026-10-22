`timescale 1ns/1ps
// Independent bus transactions: no forced internal mapper state or counters.
module fds_irq_bus_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg ce=0, enable=0, wr=0, rd=0, fast=0;
  reg [15:0] address=0;
  reg [7:0] data=0;
  tri [7:0] result;
  tri irq;
  wire [63:0] state_word;
  reg [11:0] timer_before;
  integer checks=0, failures=0, ticks=0;
  MapperFDS dut(
    .clk(clk),.ce(ce),.enable(enable),.flags(32'b0),
    .prg_ain(address),.prg_aout_b(),.prg_read(rd),.prg_write(wr),
    .prg_din(data),.prg_dout_b(result),.prg_allow_b(),
    .chr_ain(14'b0),.chr_aout_b(),.chr_read(1'b0),.chr_allow_b(),
    .vram_a10_b(),.vram_ce_b(),.irq_b(irq),
    .audio_in(16'b0),.audio_b(),.flags_out_b(),.prg_dbus(8'h5a),.audio_dout(8'b0),
    .diskside_b(),.max_diskside(2'b0),.fds_busy(1'b0),.fds_eject_btn(1'b0),
    .fds_auto_eject_en(1'b0),.fds_fast(fast),
    .SaveStateBus_Din(64'b0),.SaveStateBus_Adr(10'd34),
    .SaveStateBus_wren(1'b0),.SaveStateBus_rst(1'b0),
    .SaveStateBus_load(1'b0),.SaveStateBus_Dout(state_word)
  );
  task pulse;
    @(negedge clk);ce=1;
    @(negedge clk);ce=0;
  endtask
  task write_reg(input [15:0] a,input [7:0] v);
    @(negedge clk);address=a;data=v;wr=1;
    pulse();wr=0;
  endtask
  task read_reg(input [15:0] a);
    @(negedge clk);address=a;rd=1;
    pulse();rd=0;
    pulse(); // Status acknowledgment is registered into the next CPU cycle.
  endtask
  task check(input bit condition,input string name);
    checks++;
    if(!condition)failures++;
    $display("CHECK %s %s",condition?"PASS":"FAIL",name);
  endtask
  task reset_drive;
    @(negedge clk);enable=0;ce=0;wr=0;rd=0;
    repeat(4)@(negedge clk);
    enable=1;write_reg(16'h4023,8'h83);
  endtask
  task pending_write_irq;
    reset_drive();
    write_reg(16'h4025,8'ha1); // Write mode, transfer off.
    write_reg(16'h4025,8'he1); // Transfer starts with a byte request.
    address=16'h4030;#1;
    check(irq && result[7],"write-transfer request asserts disk IRQ and status");
  endtask
  task read_transfer(input bit speed);
    reset_drive();fast=speed;
    write_reg(16'h4025,8'he5); // Motor on, read mode, IRQ and transfer enabled.
    ticks=0;
    while(!irq && ticks<526000)begin pulse();ticks++;end
    check(irq,speed?"fast disk byte arrival":"normal disk byte arrival");
    address=16'h4030;#1;
    check(result[7] && !result[0],"read-transfer status distinguishes disk from timer IRQ");
    read_reg(16'h4031);
    check(!irq,"data read acknowledges disk IRQ");
    ticks=0;
    while(!irq && ticks<200)begin pulse();ticks++;end
    check(irq && ticks>90,"next disk byte requests another IRQ");
    read_reg(16'h4030);
    check(!irq,"status read acknowledges disk IRQ");
  endtask
  initial begin
    reset_drive(); address=16'h6000;
    repeat(4095)pulse();
    check(!irq,"watchdog waits all 4095 reset cycles");
    pulse();address=16'h4030;#1;
    check(irq && result[1] && !result[0] && !result[7],"watchdog underflow has independent IRQ status");
    write_reg(16'h4025,8'h06);address=16'h4030;#1;
    check(irq && result[1],"disk control write preserves watchdog IRQ");
    read_reg(16'h4031);
    check(irq,"disk data read preserves watchdog IRQ");
    read_reg(16'h4030);
    check(!irq,"status read acknowledges watchdog IRQ");
    address=16'h8000;repeat(4096)pulse();
    check(irq,"watchdog keeps counting and retriggers");
    timer_before=state_word[43:32];
    write_reg(16'h4023,8'h03);
    check(!irq && state_word[43:32]==timer_before-12'd1,"watchdog mask acknowledges without resetting timer");
    address=16'hdfff;repeat(5000)pulse();
    check(!irq,"watchdog mask suppresses further IRQs");
    write_reg(16'h4023,8'h82);
    check(state_word[50:32]==19'd4095 && !irq,"disk I/O reset resets both watchdog counters");
    write_reg(16'h4023,8'h83);address=16'h0000;
    repeat(127)pulse();
    check(state_word[50:44]==127 && state_word[43:32]==3968,"external CPU accesses advance refresh rows");
    pulse();
    check(state_word[50:44]==0 && state_word[43:32]==3245,"128th refresh reloads hardware value 3245");
    address=16'hdfff;repeat(3245)pulse();
    check(!irq && state_word[50:44]==0,"PRG-RAM accesses do not refresh rows");
    pulse();check(irq,"reloaded watchdog expires after 3246 CPU cycles");
    write_reg(16'h4023,8'h82);
    repeat(5000)pulse();
    check(!irq && state_word[50:32]==19'd4095,"watchdog held in reset while disk I/O disabled");
    write_reg(16'h4023,8'h83);address=16'he000;
    repeat(10000)pulse();
    check(!irq,"BIOS ROM execution provides refreshes");
    reset_drive();
    write_reg(16'h4020,8'h08);write_reg(16'h4021,8'h00);
    write_reg(16'h4022,8'h02);
    repeat(10)pulse();
    address=16'h4030;#1;
    check(irq && result[0] && !result[7],"one-shot timer IRQ status");
    read_reg(16'h4031);
    check(irq,"disk data read preserves timer IRQ");
    read_reg(16'h4030);
    check(!irq,"status read acknowledges timer IRQ");
    repeat(20)pulse();
    check(!irq,"one-shot timer does not repeat");
    write_reg(16'h4022,8'h03);repeat(10)pulse();
    read_reg(16'h4030);repeat(10)pulse();
    check(irq,"repeat timer retriggers after acknowledgment");
    write_reg(16'h4023,8'h82);
    check(!irq,"disabling disk I/O clears timer IRQ");
    pending_write_irq();write_reg(16'h4024,8'h00);
    check(!irq,"disk data write acknowledges disk IRQ");
    pending_write_irq();read_reg(16'h4031);
    check(!irq,"disk data read acknowledges write-mode disk IRQ");
    pending_write_irq();write_reg(16'h4025,8'he1);
    check(!irq,"disk control write acknowledges disk IRQ");
    pending_write_irq();write_reg(16'h4023,8'h82);
    check(!irq,"disabling disk I/O masks disk IRQ");
    read_transfer(0);read_transfer(1);
    $display("SUMMARY checks=%0d failures=%0d",checks,failures);
    if(failures)$fatal(1,"FDS IRQ bus accuracy failures");
    $finish;
  end
endmodule
