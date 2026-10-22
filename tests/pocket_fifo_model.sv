// Simulation-only FIFO contracts: registered reads, low chunks first, and
// five clock synchronizer latency. This is not Intel's device implementation.
module dcfifo_mixed_widths #(
  parameter intended_device_family="Cyclone V", lpm_numwords=4,
  parameter lpm_showahead="OFF", lpm_type="dcfifo_mixed_widths",
  parameter lpm_width=32, lpm_widthu=2, lpm_widthu_r=2, lpm_width_r=32,
  parameter overflow_checking="OFF", underflow_checking="ON", use_eab="ON",
  parameter rdsync_delaypipe=5, wrsync_delaypipe=5, write_aclr_synch="ON",
  parameter clocks_are_synchronized="FALSE"
)(input [lpm_width-1:0] data, input rdclk, rdreq, wrclk, wrreq,
  input aclr, output reg [lpm_width_r-1:0] q=0,
  output wire rdempty, wrempty, wrfull);
  localparam UNIT = (lpm_width < lpm_width_r) ? lpm_width : lpm_width_r;
  localparam WUNITS=lpm_width/UNIT, RUNITS=lpm_width_r/UNIT;
  localparam CAPACITY=lpm_numwords*WUNITS;
  reg [UNIT-1:0] mem [0:CAPACITY-1];
  integer wp=0, rp=0, overflow_count=0, underflow_count=0;
  integer wp_sync[0:4]='{default:0}, rp_sync[0:4]='{default:0};
  assign rdempty = (wp_sync[4]-rp < RUNITS);
  assign wrempty = (wp == rp_sync[4]);
  assign wrfull = (wp-rp_sync[4]+WUNITS>CAPACITY);
  always @(posedge wrclk or posedge aclr) begin
    if (aclr) begin wp <= 0; rp_sync <= '{default:0}; end
    else begin
      rp_sync[0]<=rp;
      for(integer j=1;j<5;j=j+1) rp_sync[j]<=rp_sync[j-1];
      if(wrreq) begin
        if(wp-rp_sync[4]+WUNITS>CAPACITY) overflow_count<=overflow_count+1;
        else begin
          for(integer j=0;j<WUNITS;j=j+1) mem[(wp+j)%CAPACITY]<=data[j*UNIT+:UNIT];
          wp<=wp+WUNITS;
        end
      end
    end
  end
  always @(posedge rdclk or posedge aclr) begin
    if(aclr) begin rp<=0; wp_sync<='{default:0}; q<=0; end
    else begin
      wp_sync[0]<=wp;
      for(integer j=1;j<5;j=j+1) wp_sync[j]<=wp_sync[j-1];
      if(rdreq) begin
        if(rdempty) underflow_count<=underflow_count+1;
        else begin
          for(integer j=0;j<RUNITS;j=j+1) q[j*UNIT+:UNIT]<=mem[(rp+j)%CAPACITY];
          rp<=rp+RUNITS;
        end
      end
    end
  end
endmodule

module dcfifo #(
  parameter clocks_are_synchronized="FALSE", intended_device_family="Cyclone V",
  parameter lpm_numwords=4, lpm_showahead="OFF", lpm_type="dcfifo",
  parameter lpm_width=32, lpm_widthu=2, overflow_checking="OFF",
  parameter rdsync_delaypipe=5, underflow_checking="OFF", use_eab="OFF", wrsync_delaypipe=5
)(input [lpm_width-1:0] data, input rdclk, rdreq, wrclk, wrreq,
  output [lpm_width-1:0] q, output rdempty, wrempty);
  dcfifo_mixed_widths #(.lpm_numwords(lpm_numwords), .lpm_width(lpm_width),
    .lpm_width_r(lpm_width)) impl(.*,.aclr(1'b0),.wrfull());
endmodule

module altddio_out #(parameter extend_oe_disable="OFF", intended_device_family="Cyclone V",
  invert_output="OFF", lpm_hint="UNUSED", lpm_type="altddio_out", oe_reg="UNREGISTERED",
  power_up_high="OFF", width=1)(input [width-1:0] datain_h,datain_l,
  input outclock,aclr,aset,oe,outclocken,sclr,sset, output [width-1:0] dataout);
  assign dataout=outclock ? datain_h : datain_l;
endmodule
