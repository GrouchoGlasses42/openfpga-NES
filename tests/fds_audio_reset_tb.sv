`timescale 1ns/1ps
module fds_audio_reset_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg m2=0, reset=1, wr=0;
  reg [15:0] address=0;
  reg [7:0] data=0;
  wire [7:0] result, state_out;
  wire [11:0] audio;
  reg state_read=0, state_write=0;
  reg [7:0] state_address=0, state_in=0;
  integer checks=0, failures=0;
  fds_audio dut(.clk(clk),.m2(m2),.reset(reset),.wr(wr),
    .addr_in(address),.data_in(data),.data_out(result),.audio_out(audio),
    .Savestate_MAPRAMactive(1'b0),.Savestate_MAPRAMAddr(state_address),
    .Savestate_MAPRAMRdEn(state_read),.Savestate_MAPRAMWrEn(state_write),
    .ss_di(state_in),.ss_do(state_out));
  task tick;
    @(negedge clk);m2=1;@(negedge clk);m2=0;
  endtask
  task write_reg(input [15:0] a,input [7:0] v);
    @(negedge clk);address=a;data=v;wr=1;tick();wr=0;
  endtask
  task check(input bit condition,input string name);
    checks++;if(!condition)failures++;
    $display("CHECK %s %s",condition?"PASS":"FAIL",name);
  endtask
  initial begin
    repeat(4)@(negedge clk);reset=0;
    write_reg(16'h4023,8'h81);
    write_reg(16'h4089,8'h80);write_reg(16'h4040,8'h3f);
    address=16'h4040;#1;check(result==63,"wave RAM writable during audio reset");
    write_reg(16'h4082,8'hff);write_reg(16'h4083,8'h0f);
    write_reg(16'h4084,8'h9f);address=16'h4092;#1;
    check(result==8'h5f,"modulation envelope writable during reset");
    write_reg(16'h4086,8'h23);write_reg(16'h4087,8'h81);
    write_reg(16'h408a,8'h17);
    write_reg(16'h4085,8'h6f);address=16'h4097;#1;
    check(result==8'h6f,"bias write briefly visible during reset");
    tick();#1;check(result==0,"audio reset clears modulation bias again");
    write_reg(16'h4080,8'hbf);address=16'h4090;#1;
    check(result==8'h40 && audio==0,"reset holds volume at zero even after gain write");
    address=16'h4091;repeat(100)tick();#1;
    check(result==0,"reset holds wave accumulator at zero");
    write_reg(16'h4089,8'h00);
    write_reg(16'h4023,8'h83);write_reg(16'h4080,8'hbf);
    repeat(20)tick();
    check(audio!=0,"audio resumes using wave RAM initialized while reset");
    address=16'h4091;#1;check(result!=0,"wave frequency initialized while reset advances phase");
    state_read=1;state_address=5;repeat(2)@(negedge clk);
    check(state_out==8'h23,"modulation frequency retained across audio reset");
    state_address=8'h11;repeat(2)@(negedge clk);
    check(state_out==8'h17,"envelope speed writable during reset");
    write_reg(16'h4023,8'h81);address=16'h4090;#1;
    check(audio==0 && result==8'h40,"disabling active audio immediately resets gain and mutes output");
    address=16'h4091;#1;check(result==0,"disabling active audio resets wave phase");
    state_address=8'h17;repeat(2)@(negedge clk);
    check(state_out==1,"audio reset latch is serialized");
    write_reg(16'h4023,8'h83);
    state_address=8'h17;state_in=1;state_write=1;
    @(negedge clk);state_write=0;repeat(2)@(negedge clk);
    check(state_out==1 && audio==0,"Memory restore restores audio reset latch");
    $display("SUMMARY checks=%0d failures=%0d",checks,failures);
    if(failures)$fatal(1,"FDS audio reset failures");
    $finish;
  end
endmodule
