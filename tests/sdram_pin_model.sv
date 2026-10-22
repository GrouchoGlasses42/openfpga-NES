// Simulation-only SDRAM model for the core's fixed single-word / CAS=2 mode.
module sdram_pin_model(input clk,input [12:0] address,input [1:0] bank,
  input rasn,casn,wen,dqml,dqmh,input [15:0] data_in,output reg [15:0] data_out=0);
  reg [15:0] ram[0:2097151];
  reg [12:0] rows[0:3];
  integer latency=0,read_index=0;
  wire [23:0] index_full={bank,address[8:0],rows[bank]};
  wire [20:0] index_now=index_full[20:0];
  always @(negedge clk) begin
    if(latency>0) begin
      latency<=latency-1;
      if(latency==1) data_out<=ram[read_index];
    end
    case({rasn,casn,wen})
      3'b011: rows[bank]<=address;
      3'b101: begin read_index<=index_now; latency<=2; end
      3'b100: begin
        if(!dqml) ram[index_now][7:0]<=data_in[7:0];
        if(!dqmh) ram[index_now][15:8]<=data_in[15:8];
      end
      default: begin end
    endcase
  end
endmodule
