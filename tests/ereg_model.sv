// Simulation equivalent of rtl/upstream/bus_savestates.vhd's register interface.
import regs_savestates::*;
module eReg_SavestateV #(
    parameter Adr = 0,
    parameter [63:0] def = 0
) (
    input clk, input [63:0] BUS_Din, input [9:0] BUS_Adr,
    input BUS_wren, BUS_rst, output [63:0] BUS_Dout,
    input [63:0] Din, output reg [63:0] Dout = def
);
  always @(posedge clk) begin
    if (BUS_rst) Dout <= def;
    else if (BUS_wren && BUS_Adr == Adr) Dout <= BUS_Din;
  end
  assign BUS_Dout = BUS_Adr == Adr ? Din : 64'b0;
endmodule
