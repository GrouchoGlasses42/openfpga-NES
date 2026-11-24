`timescale 1ns/1ps
// Automatic disk-side selection with synthetic disk headers. The lookup runs the
// patched BIOS bytes that the mapper supplies, so it needs no BIOS or disk image.
module fds_side_lookup_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg ce=0, enable=0, wr=0, rd=0, eject=0, auto_swap=1;
  reg [1:0] max_side=3;
  reg [15:0] address=0;
  reg [7:0] data=0;
  reg [63:0] state_in=0;
  reg [9:0] state_address=32;
  reg state_write=0, state_load=0;
  wire [63:0] state_out;
  tri0 [21:0] prg_addr;
  tri0 prg_allow;
  tri0 [1:0] side;
  tri1 [7:0] result;
  reg [7:0] disk [0:262143];
  wire [7:0] ram=(prg_allow && prg_addr[21:18]==4'hf) ? disk[prg_addr[17:0]] : 8'h00;
  MapperFDS dut(
    .clk(clk),.ce(ce),.enable(enable),.flags(32'b0),
    .prg_ain(address),.prg_aout_b(prg_addr),.prg_read(rd),.prg_write(wr),
    .prg_din(data),.prg_dout_b(result),.prg_allow_b(prg_allow),
    .chr_ain(14'b0),.chr_aout_b(),.chr_read(1'b0),.chr_allow_b(),
    .vram_a10_b(),.vram_ce_b(),.irq_b(),
    .audio_in(16'b0),.audio_b(),.flags_out_b(),.prg_dbus(ram),.audio_dout(8'b0),
    .diskside_b(side),.max_diskside(max_side),.fds_busy(1'b0),.fds_eject_btn(eject),
    .fds_auto_eject_en(auto_swap),.fds_fast(1'b0),
    .SaveStateBus_Din(state_in),.SaveStateBus_Adr(state_address),
    .SaveStateBus_wren(state_write),.SaveStateBus_rst(1'b0),
    .SaveStateBus_load(state_load),.SaveStateBus_Dout(state_out)
  );
  integer checks=0, failures=0, i, j, n;
  integer steps, save_at;
  reg [79:0] request;
  reg [63:0] saved [0:2];

  task check(input bit condition,input string name);
    checks++;
    if(!condition) begin failures++; $display("CHECK FAIL %s (side=%0d)",name,side); end
  endtask
  task pulse;
    @(negedge clk);ce=1;
    @(negedge clk);ce=0;
  endtask
  task write_reg(input [15:0] a,input [7:0] v);
    @(negedge clk);address=a;data=v;wr=1;pulse();wr=0;
  endtask
  task read_reg(input [15:0] a);
    @(negedge clk);address=a;rd=1;pulse();rd=0;
  endtask
  task fetch(input [15:0] a,output [7:0] v);
    @(negedge clk);address=a;rd=1;#1;v=result;pulse();rd=0;
  endtask
  // Save the drive state, disturb it with a reset, and restore it.
  task state_roundtrip;
    for(n=0;n<3;n++) begin state_address=32+n;#1;saved[n]=state_out;end
    @(negedge clk);enable=0;repeat(3)@(negedge clk);enable=1;
    for(n=0;n<3;n++) begin
      @(negedge clk);state_write=1;state_address=32+n;state_in=saved[n];
    end
    @(negedge clk);state_write=0;state_load=1;
    @(negedge clk);state_load=0;
  endtask
  // Execute the routine at $F4D6. Only the instructions it uses are modeled,
  // including the dummy read that a 6502 makes before an indexed store.
  task run_lookup(input [79:0] id);
    reg [15:0] pc, operand;
    reg [7:0] op, lo, hi, acc, y;
    bit done;
    request=id;pc=16'hf4d6;y=0;acc=0;steps=0;done=0;
    fetch(16'he445,op);fetch(16'he446,lo);fetch(16'he447,hi);
    check(op==8'h20 && {hi,lo}==16'hf4d6,"disk-ID check calls the lookup");
    while(!done && steps<400) begin
      fetch(pc,op);fetch(pc+1,lo);fetch(pc+2,hi);operand={hi,lo};
      case(op)
        8'ha0: begin y=lo;pc=pc+2;end
        8'hb1: begin acc=request[8*(9-y) +: 8];pc=pc+2;end
        8'h99: begin read_reg(operand+y);write_reg(operand+y,acc);pc=pc+3;end
        8'hb9: begin
          @(negedge clk);address=operand+y;rd=1;#1;acc=ram;pulse();rd=0;pc=pc+3;
        end
        8'h88: begin y=y-1;pc=pc+1;end
        8'h10: pc=pc+2+(y[7] ? 16'd0 : {{8{lo[7]}},lo});
        8'h8d: begin write_reg(operand,acc);pc=pc+3;end
        8'h4c: begin check(operand==16'he6e3,"lookup continues with the BIOS transfer");done=1;end
        default: begin check(0,"unexpected instruction");done=1;end
      endcase
      steps++;
      if(steps==save_at) state_roundtrip();
    end
    check(done,"lookup ends");
  endtask
  task expect_side(input [79:0] id,input [1:0] wanted,input string name);
    run_lookup(id);
    check(side==wanted,name);
  endtask
  // ID order: manufacturer, four name bytes, version, side, disk, two others.
  task header(input integer s,input [79:0] id);
    for(i=0;i<10;i++) disk[16+65500*s+15+i]=id[8*(9-i) +: 8];
  endtask
  task reset_drive;
    @(negedge clk);enable=0;repeat(3)@(negedge clk);enable=1;save_at=-1;
    write_reg(16'h4023,8'h83);write_reg(16'h4025,8'h2e);
  endtask
  localparam [79:0] BOOT=80'hffffffffffff0000ffff;
  function [79:0] id(input [31:0] name,input [7:0] s,d);
    id={8'h01,name,8'h00,s,d,16'h0};
  endfunction
  reg [79:0] target;
  initial begin
    for(i=0;i<262144;i++) disk[i]=8'h5a;

    // Two disks whose headers differ only in the game name.
    header(0,id("AB1 ",0,0));header(1,id("AB1 ",1,0));
    header(2,id("AB2 ",0,0));header(3,id("AB2 ",1,0));
    reset_drive();
    expect_side(id("AB1 ",1,0),1,"name: disk 1 side B");
    expect_side(id("AB2 ",0,0),2,"name: disk 2 side A");
    expect_side(id("AB2 ",1,0),3,"name: disk 2 side B");
    expect_side(id("AB1 ",0,0),0,"name: disk 1 side A");
    expect_side(id("AB2 ",1,0),3,"name: disk 1 to disk 2 side B");
    expect_side(id("ZZZ ",0,0),3,"unknown game keeps the inserted side");
    expect_side(BOOT,0,"boot request inserts the first side");
    expect_side(80'h01_41423220_00_01_ff_ffff,3,"wildcard disk byte");
    expect_side(80'hff_41423220_ff_00_ff_ffff,2,"wildcard maker and version");
    write_reg(16'h4027,1);check(side==2,"no direct side register at $4027");

    // Each ID byte must take part in the comparison.
    for(j=0;j<10;j++) begin
      target=id("AB2 ",1,0);
      expect_side(id("AB1 ",0,0),0,"single byte: start");
      disk[16+65500*3+15+j]=disk[16+65500*3+15+j]^8'h40;
      expect_side(target,0,"single byte: mismatch rejected");
      disk[16+65500*3+15+j]=disk[16+65500*3+15+j]^8'h40;
      expect_side(target,3,"single byte: match accepted");
    end

    // A save state can be taken at any point in the lookup.
    for(j=1;j<90;j++) begin
      save_at=-1;expect_side(id("AB1 ",0,0),0,"state: start");
      save_at=j;run_lookup(id("AB2 ",1,0));
      check(side==3,"state: restored during lookup");
    end
    reset_drive();

    // Two disks that differ only in the disk number.
    header(0,id("CDE ",0,0));header(1,id("CDE ",1,0));
    header(2,id("CDE ",0,1));header(3,id("CDE ",1,1));
    expect_side(id("CDE ",1,1),3,"number: disk 2 side B");
    expect_side(id("CDE ",0,1),2,"number: disk 2 side A");
    expect_side(id("CDE ",1,0),1,"number: disk 1 side B");
    expect_side(id("CDE ",0,0),0,"number: disk 1 side A");

    // Data that remains beyond the loaded sides must not match.
    for(n=0;n<4;n++) begin
      max_side=n;reset_drive();
      for(j=0;j<4;j++) begin
        reset_drive();
        expect_side(id("CDE ",j&1,j>>1),j<=n ? j : 0,"absent sides are ignored");
      end
    end
    max_side=3;

    // Identical headers: use the first side.
    for(j=0;j<4;j++) header(j,id("SAM ",0,0));
    reset_drive();expect_side(id("SAM ",0,0),0,"identical headers");
    for(j=0;j<4;j++) header(j,id("CDE ",j&1,j>>1));

    // Outside a lookup the window is not mapped.
    for(i=16'h40c0;i<=16'h40ff;i++) begin
      @(negedge clk);address=i;rd=1;#1;check(!prg_allow,"window idle");rd=0;
    end
    write_reg(16'h40bf,0);check(side==0,"commit alone has no effect");

    // Manual mode: the lookup never changes the side; the button uses all sides.
    auto_swap=0;reset_drive();
    for(j=1;j<=5;j++) begin
      @(negedge clk);eject=1;pulse();pulse();eject=0;pulse();
      check(side==(j&3),"manual: next side");
      run_lookup(id("CDE ",0,0));
      check(side==(j&3),"manual: lookup does not change the side");
    end

    $display("RESULT %0d checks, %0d failures",checks,failures);
    if(failures) $fatal(1,"FDS side lookup failed");
    $display("PASS: FDS automatic side lookup");
    $finish;
  end
endmodule
