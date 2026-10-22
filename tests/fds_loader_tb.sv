`timescale 1ns/1ps
module fds_loader_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1, downloading = 0, indata_clk = 0;
  reg [7:0] stream_byte = 0;
  wire [24:0] mem_addr;
  wire [7:0] mem_data;
  wire mem_write, busy, done, error, rom_loaded;
  wire [63:0] mapper_flags;
  wire [9:0] prg_mask, chr_mask;
  // Model the synchronous BIOS RAM. The copy engine leaves 16 clocks per byte.
  reg [7:0] bios_data;
  always @(posedge clk) bios_data <= mem_addr[7:0] ^ 8'ha5;
  wire [7:0] indata = (busy && !downloading) ? bios_data : stream_byte;
  GameLoader dut(.clk(clk), .reset(reset), .downloading(downloading),
    .filetype(8'h04), .is_bios(1'b0), .indata(indata), .indata_clk(indata_clk),
    .clearval(1'b0), .cleardata(8'b0), .mem_addr(mem_addr), .mem_data(mem_data),
    .mem_write(mem_write), .mapper_flags(mapper_flags), .prg_mask(prg_mask),
    .chr_mask(chr_mask), .busy(busy), .done(done), .error(error), .rom_loaded(rom_loaded));

  integer bios_writes = 0;
  integer disk_writes = 0;
  reg [7:0] first_disk_byte = 0;
  reg [7:0] last_disk_byte = 0;
  reg [24:0] last_disk_address = 0;
  always @(posedge clk) if (!reset && mem_write) begin
    if (mem_addr < 8192) begin
      if (mem_data !== (mem_addr[7:0] ^ 8'ha5))
        $fatal(1, "Incorrect BIOS copy at %h: %h", mem_addr, mem_data);
      bios_writes = bios_writes + 1;
    end
    if (mem_addr >= 25'h3c0010 && mem_addr < 25'h400000) begin
      disk_writes = disk_writes + 1;
      if (mem_addr == 25'h3c0010) first_disk_byte = mem_data;
      last_disk_byte = mem_data;
      last_disk_address = mem_addr;
    end
  end

  task send_byte(input [7:0] value);
    begin
      @(negedge clk); stream_byte = value; indata_clk = 1;
      @(negedge clk); indata_clk = 0;
      repeat (3) @(negedge clk);
    end
  endtask

  task run_disk(input bit header, input integer sides);
    integer n, limit;
    begin
      @(negedge clk); reset = 1; downloading = 0;
      repeat (3) @(negedge clk);
      bios_writes = 0; disk_writes = 0;
      reset = 0; downloading = 1;
      if (header) begin
        send_byte(8'h46); send_byte(8'h44); send_byte(8'h53); send_byte(8'h1a);
        send_byte(sides);
        for (n = 5; n < 16; n = n + 1) send_byte(0);
      end
      for (n = 0; n < sides * 65500; n = n + 1) send_byte(n[7:0]);
      downloading = 0;
      limit = 0;
      while (!done && limit < 200000) begin
        @(negedge clk); limit = limit + 1;
      end
      if (!done || error) $fatal(1, "FDS loader failed or timed out");
      if (mapper_flags[7:0] !== 8'd20) $fatal(1, "FDS mapper not selected");
      if (bios_writes != 8192) $fatal(1, "Copied %0d BIOS bytes", bios_writes);
      if (first_disk_byte !== 0) $fatal(1, "Header not removed from disk data");
      if (last_disk_address !== 25'h3c000f + sides * 65500)
        $fatal(1, "Disk boundary mismatch: %h", last_disk_address);
      if (last_disk_byte !== ((sides * 65500 - 1) & 255))
        $fatal(1, "Last disk byte mismatch");
      $display("PASS: FDS header=%0d sides=%0d, disk data and BIOS copy", header, sides);
    end
  endtask

  initial begin
    run_disk(1, 1);
    run_disk(0, 2);
    run_disk(1, 4);
    $finish;
  end
endmodule
