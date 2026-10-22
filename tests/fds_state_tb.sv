`timescale 1ns/1ps
module fds_state_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg ce = 0, enable = 0, prg_write = 0;
  reg [15:0] address = 0;
  reg [7:0] data = 0;
  reg [63:0] state_in = 0;
  reg [9:0] state_address = 0;
  reg state_write = 0, state_reset = 0, state_load = 0;
  wire [63:0] state_out;
  tri0 [21:0] prg_addr, chr_addr;
  tri0 prg_allow, chr_allow, vram_a10, vram_ce, irq;
  tri1 [7:0] prg_data;
  tri0 [15:0] flags_out, audio_bus;
  tri0 [1:0] diskside;
  wire [15:0] audio;
  wire [7:0] audio_data;
  reg ram_active = 0, ram_write = 0;
  reg [7:0] ram_address = 0, ram_in = 0;
  wire [7:0] ram_out;
  reg [63:0] saved_drive [0:2];
  reg [7:0] saved_audio [0:255];

  MapperFDS drive(.clk(clk), .ce(ce), .enable(enable), .flags(64'b0),
    .prg_ain(address), .prg_aout_b(prg_addr), .prg_read(1'b0), .prg_write(prg_write),
    .prg_din(data), .prg_dout_b(prg_data), .prg_allow_b(prg_allow),
    .chr_ain(14'b0), .chr_aout_b(chr_addr), .chr_read(1'b0), .chr_allow_b(chr_allow),
    .vram_a10_b(vram_a10), .vram_ce_b(vram_ce), .irq_b(irq), .flags_out_b(flags_out),
    .audio_in(audio), .audio_b(audio_bus), .prg_dbus(8'b0), .audio_dout(audio_data),
    .diskside_b(diskside), .max_diskside(2'd3), .fds_busy(1'b0),
    .fds_eject_btn(1'b0), .fds_auto_eject_en(1'b0), .fds_fast(1'b0),
    .SaveStateBus_Din(state_in), .SaveStateBus_Adr(state_address),
    .SaveStateBus_wren(state_write), .SaveStateBus_rst(state_reset),
    .SaveStateBus_load(state_load), .SaveStateBus_Dout(state_out));

  fds_mixed sound(.clk(clk), .ce(ce), .enable(enable), .wren(prg_write),
    .addr_in(address), .data_in(data), .data_out(audio_data), .audio_in(16'h8000),
    .audio_out(audio), .Savestate_MAPRAMactive(ram_active),
    .Savestate_MAPRAMAddr(ram_address), .Savestate_MAPRAMRdEn(1'b1),
    .Savestate_MAPRAMWrEn(ram_write), .Savestate_MAPRAMWriteData(ram_in),
    .Savestate_MAPRAMReadData(ram_out));

  task cpu_write(input [15:0] addr, input [7:0] value);
    @(negedge clk); ce = 1; prg_write = 1; address = addr; data = value;
    @(negedge clk); ce = 0; prg_write = 0;
    repeat (2) @(negedge clk);
  endtask

  integer i;
  initial begin
    repeat (4) @(negedge clk);
    enable = 1;
    cpu_write(16'h4023, 8'h83);
    cpu_write(16'h4020, 8'h34);
    cpu_write(16'h4021, 8'h12);
    cpu_write(16'h4022, 3);
    cpu_write(16'h4025, 8'h46);
    cpu_write(16'h4089, 8'h80);
    for (i = 0; i < 64; i = i + 1) cpu_write(16'h4040 + i, i);
    cpu_write(16'h4023, 8'h81);
    address = 16'h6000;
    for (i = 0; i < 4096; i = i + 1) begin
      @(negedge clk); ce = 1;
      @(negedge clk); ce = 0;
    end
    if (!irq) $fatal(1, "Watchdog IRQ not pending before save");
    ram_active = 1;
    for (i = 0; i < 3; i = i + 1) begin
      state_address = 32 + i; #1; saved_drive[i] = state_out;
    end
    if (saved_drive[0][34:19] != 16'h1234) $fatal(1, "Timer programming failed");
    for (i = 0; i < 256; i = i + 1) begin
      @(negedge clk); ram_address = i;
      @(negedge clk); saved_audio[i] = ram_out;
    end
    cpu_write(16'h4020, 8'hff);
    cpu_write(16'h4021, 8'hee);
    for (i = 0; i < 256; i = i + 1) begin
      @(negedge clk); ram_write = 1; ram_address = i; ram_in = ~saved_audio[i];
    end
    @(negedge clk); ram_write = 0;
    // Restore the serialized register bus, then issue the drive load pulse.
    for (i = 0; i < 3; i = i + 1) begin
      @(negedge clk); state_write = 1; state_address = 32 + i; state_in = saved_drive[i];
    end
    @(negedge clk); state_write = 0; state_load = 1;
    @(negedge clk); state_load = 0;
    for (i = 0; i < 3; i = i + 1) begin
      state_address = 32 + i; #1;
      if (state_out !== saved_drive[i]) $fatal(1, "Drive state word %0d did not restore", i);
    end
    for (i = 0; i < 256; i = i + 1) begin
      @(negedge clk); ram_write = 1; ram_address = i; ram_in = saved_audio[i];
    end
    @(negedge clk); ram_write = 0;
    for (i = 0; i < 256; i = i + 1) begin
      @(negedge clk); ram_address = i;
      @(negedge clk);
      if (ram_out !== saved_audio[i]) $fatal(1, "FDS audio state byte %0d did not restore", i);
    end
    $display("PASS: FDS drive registers, sound state and wave/modulation RAM restore");
    $finish;
  end
endmodule
