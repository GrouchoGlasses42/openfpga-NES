// Reserve memory before acknowledging a persistent-save transfer. The NES
// pauses at a safe CPU/video boundary, so a pause request alone is not ready.
module save_transfer_controller (
    input wire clk_74a, clk_ppu_21_47,
    input wire clock_locked,
    input wire requestread, requestwrite,
    input wire [15:0] requestread_id, requestwrite_id,
    input wire allcomplete,
    input wire memory_ready,
    output wire requestread_ack, requestwrite_ack,
    output wire active, loading
);
  reg transfer_active = 0;
  reg transfer_loading = 0;
  wire ready_s;
  synch_3 #(.WIDTH(1)) ready_sync (
      .i(memory_ready), .o(ready_s), .clk(clk_74a), .rise(), .fall());
  synch_3 #(.WIDTH(2)) transfer_sync (
      .i({transfer_active, transfer_loading}), .o({active, loading}),
      .clk(clk_ppu_21_47), .rise(), .fall());

  wire save_read = requestread && requestread_id == 10;
  wire save_write = requestwrite && requestwrite_id == 10;
  // core_bridge_cmd first raises request and assigns its ID together. Qualify
  // every ACK with request so an old ID cannot acknowledge the new command.
  assign requestread_ack = requestread &&
      (requestread_id != 10 || (transfer_active && ready_s));
  assign requestwrite_ack = requestwrite &&
      (requestwrite_id != 10 || (transfer_active && ready_s));

  always @(posedge clk_74a) begin
    if (!clock_locked) begin
      transfer_active <= 0;
      transfer_loading <= 0;
    end else if (save_read || save_write) begin
      // Complete the previous ready/idle handshake before starting another
      // transfer, including commands that arrive immediately after completion.
      if (!transfer_active && !ready_s) begin
        transfer_active <= 1;
        transfer_loading <= save_write;
      end
    end else if (allcomplete) begin
      transfer_active <= 0;
    end
  end
endmodule
