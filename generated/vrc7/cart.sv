// Mapper top level selection

// Notes by Kitrinx:
// This module uses bidirectional ports to handle the data out of each mapper.
// Although FPGA's do not use bidirectional wiring internally, the alternative is
// creating a tenticle-monster of wires for each mapper, and muxing them all together.
// As it stands, the compiler will efficiently do it for us with much more readable and
// manageable code if we do it this way, and since not more than one mapper can be active
// at a time, there will be no conflicts.

// SDRAM Locations for various RAM types:
// PRG       = 0....
// CHR       = 10...
// CPU-RAM   = 11100
// CHR-VRAM  = 11101
// CARTRAM   = 1111

module cart_top (
	input             clk,
	input             ce,             // M2
	input             cpu_ce,         // CPU Phi1 clock (several mappers use m2 inverted)
	input             paused,         // This indicates the core is paused so anything using the master clock won't get messed up
	input             reset,
	input             vs_mode,        // Vs. motherboard memory configuration
	input      [63:0] flags,          // Misc flags from ines header {prg_size(3), chr_size(3), mapper(8)}
	input      [15:0] prg_ain,        // Better known as "CPU Address in"
	output reg [24:0] prg_aout,       // PRG Input / Output Address Lines ([25:22] extended Lines [Misc ROM])
	input             prg_read,       // PRG Read / write signals
	input             prg_write,
	input       [7:0] prg_din,        // CPU Data In
	output reg  [7:0] prg_dout,       // CPU Data Out
	input       [7:0] prg_from_ram,   // PRG Data from RAM
	output reg        prg_allow,      // PRG Allow write access
	output reg        prg_bus_write,  // PRG Data Driven
	output reg        prg_conflict,   // PRG Data is ROM & prg_din
	output reg        has_savestate,  // mapper supports savestates
	output reg        prg_conflict_d0,   // PRG Data is ROM & (prg_din | 1)
	output reg        has_flashsaves, // Homebrew mapper that saves to PRG-ROM in flash memory
	input       [9:0] prg_mask,       // PRG Mask for SDRAM translation
	input       [9:0] chr_mask,       // CHR Mask for SDRAM translation
	input             chr_ex,         // chr_addr is from an extra sprite read if high
	input             chr_read,       // Read from CHR
	input             chr_write,      // Write to CHR
	input       [7:0] chr_din,        // PPU Data In
	input      [13:0] chr_ain_orig,   // Better known as "PPU Address in"
	input      [13:0] chr_ain_ex,     // Address for extra sprite fetches
	output reg [21:0] chr_aout,       // CHR Input / Output Address Lines
	output reg  [7:0] chr_dout,       // Value to override CHR data with
	output reg        has_chr_dout,   // True if CHR data should be overridden
	output reg        chr_allow,      // CHR Allow write
	output reg        vram_a10,       // CHR Value for A10 address line
	output reg        vram_ce,        // CHR True if the address should be routed to the internal 2kB VRAM.
	output reg [17:0] mapper_addr,
	input       [7:0] mapper_data_in,
	output reg  [7:0] mapper_data_out,
	output reg        mapper_prg_write,
	output reg        mapper_ovr,
	output reg        irq,
	input      [15:0] audio_in,
	output reg [15:0] audio,          // External Audio
	output reg  [1:0] diskside,
	input             fds_busy,       // FDS Disk Swap Busy
	input             fds_eject,      // FDS Disk Swap Pause
	input             fds_auto_eject, // FDS Auto Swap Enabled
	input       [1:0] max_diskside,   // FDS disk side count
	input             fds_fast,       // FDS disk access speed
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout,
	
	input         Savestate_MAPRAMactive,     
	input  [12:0] Savestate_MAPRAMAddr,     
	input         Savestate_MAPRAMRdEn,    
	input         Savestate_MAPRAMWrEn,    
	input  [7:0]  Savestate_MAPRAMWriteData,
	output [7:0]  Savestate_MAPRAMReadData
);

tri0 prg_allow_b, vram_a10_b, vram_ce_b, chr_allow_b, irq_b;
tri0 [21:0] prg_addr_b, chr_addr_b;
tri0 [15:0] flags_out_b, audio_out_b;
tri1 [7:0] prg_dout_b, chr_dout_b;

wire [13:0] chr_ain = chr_ex ? chr_ain_ex : chr_ain_orig;
wire [2:0] prg_aoute_m413;

// These memories are on the Vs. CPU board rather than any individual ROM
// board. The CPU RAM has only eleven address inputs and therefore repeats four
// times through $6000-$7FFF. All four nametable pages are physically present.
wire vs_prg_ram = vs_mode && (prg_ain[15:13] == 3'b011);
wire vs_nametable_ram = vs_mode && chr_ain[13];
wire [21:0] vs_prg_ram_addr = {9'b11_1100_000, 2'b00, prg_ain[10:0]};
wire [21:0] vs_nametable_ram_addr = {10'b11_1111_1100, chr_ain[11:0]};

// This mapper used to be default if no other mapper was found
// It seems MMC0 is handled by map28. Does it have any purpose?
// flags_out_b will be high if no other mappers are selected, so we use that.
wire [15:0] mmc0_flags;
MMC0 mmc0(
	.clk        (clk),
	.ce         (ce),
	.enable     (1'b0),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(mmc0_flags),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
	// savestates              
	// savestates support - but no state in mapper needs saving
);

//*****************************************************************************//
// Name   : MMC1                                                               //
// Mappers: 1, 155, 171 (hard wired vertical mirroring)                        //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Simon's Quest                                                      //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[1] | POCKET_MAPPER_MASK[155] | POCKET_MAPPER_MASK[171]) begin : include_mmc1
MMC1 mmc1(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[171] | me[155] | me[1]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[0])
);
end else begin : omit_mmc1
assign SaveStateBus_wired_or[0] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Tepples                                                            //
// Mappers: 0, 2, 3, 7, 28, 94, 97, 180, 185                                   //
// Status : Working                                                            //
// Notes  : This mapper relies on open bus and bus conflict behavior.          //
// Games  : Donkey Kong                                                        //
//*****************************************************************************//
wire mapper28_en = me[0] | me[2] | me[3] | me[7] | me[94] | me[97] | me[180] | me[185] | me[28];
generate if (POCKET_MAPPER_MASK[0] | POCKET_MAPPER_MASK[2] | POCKET_MAPPER_MASK[3] | POCKET_MAPPER_MASK[7] | POCKET_MAPPER_MASK[28] | POCKET_MAPPER_MASK[94] | POCKET_MAPPER_MASK[97] | POCKET_MAPPER_MASK[180] | POCKET_MAPPER_MASK[185]) begin : include_map28
Mapper28 map28(
	.clk        (clk),
	.ce         (ce),
	.enable     (mapper28_en & ~reset),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_dout_b (chr_dout_b), // Special port
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[1])
);
end else begin : omit_map28
assign SaveStateBus_wired_or[1] = '0;
end endgenerate

//*****************************************************************************//
// Name   : UNROM 512                                                          //
// Mappers: 30                                                                 //
// Status : Self flashing except sector erase                                  //
// Notes  : Homebrew mapper                                                    //
// Games  : More Glider                                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[30]) begin : include_map30
Mapper30 map30(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[30]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[26])
);
end else begin : omit_map30
assign SaveStateBus_wired_or[26] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 32                                                          //
// Mappers: 32                                                                 //
// Status : Needs evaluation                                                   //
// Notes  :                                                                    //
// Games  : Image Fight                                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[32]) begin : include_map32
Mapper32 map32(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[32]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[28])
);
end else begin : omit_map32
assign SaveStateBus_wired_or[28] = '0;
end endgenerate

//*****************************************************************************//
// Name   : MMC2                                                               //
// Mappers: 9                                                                  //
// Status :                                                                    //
// Notes  : Working                                                            //
// Games  : Mike Tyson's Punch-Out                                             //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[9]) begin : include_mmc2
MMC2 mmc2(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[9]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	.paused     (paused),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[6])
);
end else begin : omit_mmc2
assign SaveStateBus_wired_or[6] = '0;
end endgenerate

//*****************************************************************************//
// Name   : MMC3                                                               //
// Mappers: 4, 33, 37, 45, 47, 48, 52, 74, 76, 80, 82, 88, 95, 112, 118, 119,  //
//          154, 189, 191, 192, 194, 195, 196, 205, 206, 207, 208, 268         //
// Status : Working -- Blaarg IRQ timing test fails, but may be submapper      //
// Notes  : While currently working well, this mapper could use a full review. //
// Games  : Crystalis, Battletoads                                             //
//*****************************************************************************//
wire mmc3_en = me[118] | me[119] | me[47] | me[206] | me[112] | me[88] | me[154] | me[95]
	| me[76] | me[80] | me[82] | me[207] | me[48] | me[33] | me[37] | me[74] | me[191]
	| me[192] | me[194] | me[195] | me[196] | me[4] | me[189] | me[268] | me[205] | me[208]
	| me[45] | me[52];

generate if (POCKET_MAPPER_MASK[4] | POCKET_MAPPER_MASK[33] | POCKET_MAPPER_MASK[37] | POCKET_MAPPER_MASK[45] | POCKET_MAPPER_MASK[47] | POCKET_MAPPER_MASK[48] | POCKET_MAPPER_MASK[52] | POCKET_MAPPER_MASK[74] | POCKET_MAPPER_MASK[76] | POCKET_MAPPER_MASK[80] | POCKET_MAPPER_MASK[82] | POCKET_MAPPER_MASK[88] | POCKET_MAPPER_MASK[95] | POCKET_MAPPER_MASK[112] | POCKET_MAPPER_MASK[118] | POCKET_MAPPER_MASK[119] | POCKET_MAPPER_MASK[154] | POCKET_MAPPER_MASK[189] | POCKET_MAPPER_MASK[191] | POCKET_MAPPER_MASK[192] | POCKET_MAPPER_MASK[194] | POCKET_MAPPER_MASK[195] | POCKET_MAPPER_MASK[196] | POCKET_MAPPER_MASK[205] | POCKET_MAPPER_MASK[206] | POCKET_MAPPER_MASK[207] | POCKET_MAPPER_MASK[208] | POCKET_MAPPER_MASK[268]) begin : include_mmc3
MMC3 mmc3 (
	.clk        (clk),
	.ce         (ce),
	.enable     (mmc3_en),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	.m2_inv     (cpu_ce),
	.paused     (paused),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[2])
);
end else begin : omit_mmc3
assign SaveStateBus_wired_or[2] = '0;
end endgenerate

//*****************************************************************************//
// Name   : MMC4                                                               //
// Mappers: 10                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Fire Emblem                                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[10]) begin : include_mmc4
MMC4 mmc4(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[10]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	.paused     (paused),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[7])
);
end else begin : omit_mmc4
assign SaveStateBus_wired_or[7] = '0;
end endgenerate

//*****************************************************************************//
// Name   : MMC5                                                               //
// Mappers: 5                                                                  //
// Status : Fairly complete, but has some bugs. Check Rockman Minus Infinity.  //
// Notes  : Uses expansion audio and PPU hacks. Could use a thorough review.   //
// Games  : Castlevania III, Just Breed                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[5]) begin : include_mmc5
MMC5 mmc5(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[5]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (mmc5_audio),
	.audio_b    (audio_out_b),
	// Special ports
	.audio_dout	(mmc5_data),
	.chr_ain_o  (chr_ain_orig),
	.chr_ex     (chr_ex),
	.chr_din    (chr_din),
	.chr_write  (chr_write),
	.chr_dout_b (chr_dout_b),
	.paused     (paused),
		// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[16]),
	
	.Savestate_MAPRAMactive   (Savestate_MAPRAMactive),
	.Savestate_MAPRAMAddr     (Savestate_MAPRAMAddr[9:0]),     
	.Savestate_MAPRAMRdEn     (Savestate_MAPRAMRdEn),    
	.Savestate_MAPRAMWrEn     (Savestate_MAPRAMWrEn),    
	.Savestate_MAPRAMWriteData(Savestate_MAPRAMWriteData),
	.Savestate_MAPRAMReadData (SaveStateRAM_wired_or[1])
);
end else begin : omit_mmc5
assign SaveStateBus_wired_or[16] = '0;
assign SaveStateRAM_wired_or[1] = '0;
end endgenerate

//*****************************************************************************//
// Name   : CPROM                                                              //
// Mappers: 13                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Videomation                                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[13]) begin : include_map13
Mapper13 map13(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[13]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map13

end endgenerate

//*****************************************************************************//
// Name   : Mapper 15                                                          //
// Mappers: 15                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Bao Xiao San Guo                                                   //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[15]) begin : include_map15
Mapper15 map15(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[15]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map15

end endgenerate

//*****************************************************************************//
// Name   : Bandai 16                                                          //
// Mappers: 159, 153, 16                                                       //
// Status : Working/EEPROM needs testing                                       //
// Notes  :                                                                    //
// Games  : SD Gundam Gaiden, Dragon Ball 3, Famicom Jump II                   //
//*****************************************************************************//
wire map16_prg_write, map16_ovr;
wire [7:0] map16_data_out;
wire [17:0] map16_mapper_addr;
generate if (POCKET_MAPPER_MASK[16] | POCKET_MAPPER_MASK[153] | POCKET_MAPPER_MASK[159]) begin : include_map16
Mapper16 map16(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[159] | me[153] | me[16]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special Ports
	.mapper_addr(map16_mapper_addr),
	.mapper_data_in(mapper_data_in),
	.mapper_data_out(map16_data_out),
	.mapper_prg_write(map16_prg_write),
	.mapper_ovr(map16_ovr),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[5])
);
end else begin : omit_map16
assign SaveStateBus_wired_or[5] = '0;
assign map16_mapper_addr = '0;
assign map16_data_out = '0;
assign map16_prg_write = '0;
assign map16_ovr = '0;
end endgenerate

//*****************************************************************************//
// Name   : Jaleco 18                                                          //
// Mappers: 18                                                                 //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Pizza Pop!, Plasma Ball, USA Ice Hockey in FC                      //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[18]) begin : include_map18
Mapper18 map18(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[18]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[27])
);
end else begin : omit_map18
assign SaveStateBus_wired_or[27] = '0;
end endgenerate

//*****************************************************************************//
// Name   : BNROM                                                              //
// Mappers: 34                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Mashou, Deadly Towers                                              //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[34]) begin : include_map34
Mapper34 map34(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[34]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[31])
);
end else begin : omit_map34
assign SaveStateBus_wired_or[31] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 41                                                          //
// Mappers: 41                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Caltron 6-in-1                                                     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[41]) begin : include_map41
Mapper41 map41(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[41]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map41

end endgenerate

//*****************************************************************************//
// Name   : NTDEC 2722, Mapper42                                               //
// Mappers: 40, 42                                                             //
// Status : Not working                                                        //
// Notes  : Used for converted FDS carts.                                      //
// Games  : Super Mario Bros. 2 (LF36) Love Warrior Nicol, Green Beret (unl)   //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[40] | POCKET_MAPPER_MASK[42]) begin : include_map42
Mapper42 map42(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[40] | me[42]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map42

end endgenerate

//*****************************************************************************//
// Name   : Kaiser KS202                                                       //
// Mappers: 142                                                                //
// Status : Needs evaluation                                                   //
// Notes  : Used for converted FDS carts.                                      //
// Games  : Bubble Bobble, Super Mario Bros. 2(j)                              //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[142]) begin : include_map142
KS202 map142(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[142]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map142

end endgenerate

//*****************************************************************************//
// Name   : Irem H3001                                                         //
// Mappers: 65                                                                 //
// Status : Needs evaluation                                                   //
// Notes  :                                                                    //
// Games  : Spartan X 2, Daiku no Gen-san 2                                    //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[65]) begin : include_map65
Mapper65 map65(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[65]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[29])
);
end else begin : omit_map65
assign SaveStateBus_wired_or[29] = '0;
end endgenerate

//*********************************************************************************//
// Name   : GxROM                                                                  //
// Mappers: 11, 38, 46, 66, 86, 87, 101, 140, 144                                  //
// Status : 38/66 - Working, 38/87/101/140/144 - Needs eval, 86 - No Audio Samples //
// Notes  :                                                                        //
// Games  : Doraemon, Dragon Power, Sidewinder (145), Taiwan Mahjong 16 (149)      //
//*********************************************************************************//
wire mapper66_en = me[11] | me[38] | me[46] | me[86] | me[87] | me[101] | me[140] | me[66] | me[144] | me[145] | me[149];
generate if (POCKET_MAPPER_MASK[11] | POCKET_MAPPER_MASK[38] | POCKET_MAPPER_MASK[46] | POCKET_MAPPER_MASK[66] | POCKET_MAPPER_MASK[86] | POCKET_MAPPER_MASK[87] | POCKET_MAPPER_MASK[101] | POCKET_MAPPER_MASK[140] | POCKET_MAPPER_MASK[144] | POCKET_MAPPER_MASK[145] | POCKET_MAPPER_MASK[149]) begin : include_map66
Mapper66 map66(
	.clk        (clk),
	.ce         (ce),
	.enable     (mapper66_en),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[3])
);
end else begin : omit_map66
assign SaveStateBus_wired_or[3] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sunsoft-3                                                          //
// Mappers: 67, 190                                                            //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Fantasy Zone II, Mito Koumon                                       //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[67] | POCKET_MAPPER_MASK[190]) begin : include_map67
Mapper67 map67(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[67] | me[190]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[20])
);
end else begin : omit_map67
assign SaveStateBus_wired_or[20] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sunsoft-4                                                          //
// Mappers: 68                                                                 //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : After Burner (J), Majaraja                                         //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[68]) begin : include_map68
Mapper68 map68(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[68]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[21])
);
end else begin : omit_map68
assign SaveStateBus_wired_or[21] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sunsoft FME-7                                                      //
// Mappers: 69                                                                 //
// Status : Working*                                                           //
// Notes  : Audio needs better mixing/processing                               //
// Games  : Gimmick!, Barcode World, Hebereke                                  //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[69]) begin : include_map69
Mapper69 map69(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[69]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (ss5b_audio),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[12])
);
end else begin : omit_map69
assign SaveStateBus_wired_or[12] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Codemasters/Camerica                                               //
// Mappers: 71, 232                                                            //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Micro Machines, Big Nose the Caveman                               //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[71] | POCKET_MAPPER_MASK[232]) begin : include_map71
Mapper71 map71(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[71] | me[232]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[8])
);
end else begin : omit_map71
assign SaveStateBus_wired_or[8] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Jaleco JF-17                                                       //
// Mappers: 72, 92                                                             //
// Status : 72/92 - Needs evaluation/No audio samples.                         //
// Notes  :                                                                    //
// Games  : Pro Tennis (J), Pinball Quest (J), Pro Soccer (J)                  //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[72] | POCKET_MAPPER_MASK[92]) begin : include_map72
Mapper72 map72(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[92] | me[72]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[30])
);
end else begin : omit_map72
assign SaveStateBus_wired_or[30] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 77                                                          //
// Mappers: 77                                                                 //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Napoleon Senki                                                     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[77]) begin : include_map77
Mapper77 map77(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[77]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[32])
);
end else begin : omit_map77
assign SaveStateBus_wired_or[32] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Holy Diver, NTDEC N715021                                          //
// Mappers: 78, 70, 152, 81                                                    //
// Status : Needs testing overall                                              //
// Notes  : Submapper 1 Requires NES 2.0                                       //
// Games  : Holy Diver, Uchuusent, Super Gun                                   //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[70] | POCKET_MAPPER_MASK[78] | POCKET_MAPPER_MASK[81] | POCKET_MAPPER_MASK[152]) begin : include_map78
Mapper78 map78(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[152] | me[70] | me[78] | me[81]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[33])
);
end else begin : omit_map78
assign SaveStateBus_wired_or[33] = '0;
end endgenerate

//*****************************************************************************//
// Name   : NINA                                                               //
// Mappers: 79, 113, 133, 146, 148                                             //
// Status : Working                                                            //
// Notes  : 133 uses simplified (72 pin) version, 146 Duplicate of 79?         //
// Games  : Tiles of Fate, Dudes with Attitude, Krazy Kreatures,               //
//          Twin Eagle (146), Mahjong World (148), Jovial Race (133)           //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[79] | POCKET_MAPPER_MASK[113] | POCKET_MAPPER_MASK[133] | POCKET_MAPPER_MASK[146] | POCKET_MAPPER_MASK[148]) begin : include_map79
Mapper79 map79(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[79] | me[113] | me[133] | me[146] | me[148]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[4])
);
end else begin : omit_map79
assign SaveStateBus_wired_or[4] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Cony/Yoko (unlicensed)                                             //
// Mappers: 83                                                                 //
// Status : Supports all submappers, could use further evaluation              //
// Notes  : No user ability to control dipswitch setting                       //
// Games  : Fatal Fury 2, World Heroes 2, Dragon Ball Party                    //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[83]) begin : include_map83
Mapper83 map83(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[83]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map83

end endgenerate

//*****************************************************************************//
// Name   : Sunsoft                                                            //
// Mappers: 89, 93, 184                                                        //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Tenka no Goikenban                                                 //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[89] | POCKET_MAPPER_MASK[93] | POCKET_MAPPER_MASK[184]) begin : include_map89
Mapper89 map89(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[89] | me[93] | me[184]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[34])
);
end else begin : omit_map89
assign SaveStateBus_wired_or[34] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Nintendo Vs. System ROM board                                     //
// Mappers: 99                                                                //
// Status : Mapper-only support; wider Vs. platform support is separate        //
// Notes  : OUT2 CHR select, Gumshoe PRG select, and absent-socket open bus    //
// Games  : Vs. Super Mario Bros., Gumshoe                                    //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[99]) begin : include_map99
Mapper99 map99(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[99]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_dout_b (chr_dout_b),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Savestates
	.SaveStateBus_Din  (SaveStateBus_Din),
	.SaveStateBus_Adr  (SaveStateBus_Adr),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst),
	.SaveStateBus_load (SaveStateBus_load),
	.SaveStateBus_Dout (SaveStateBus_wired_or[40])
);
end else begin : omit_map99
assign SaveStateBus_wired_or[40] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Magic Dragon                                                       //
// Mappers: 107                                                                //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Magic Dragon                                                       //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[107]) begin : include_map107
Mapper107 map107(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[107]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map107

end endgenerate

//*****************************************************************************//
// Name   : GTROM                                                              //
// Mappers: 111                                                                //
// Status : Passes all tests except flash sector erase                         //
// Notes  : No LED or flash sector erase                                       //
// Games  : Super Homebrew War, Candelabra: Estoscerro, more homebrew          //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[111]) begin : include_map111
Mapper111 map111(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[111]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[25])
);
end else begin : omit_map111
assign SaveStateBus_wired_or[25] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 165                                                         //
// Mappers: 165                                                                //
// Status : Working                                                            //
// Notes  : Possibly merge-able with MMC3, only used for one bootleg game      //
// Games  : Fire Emblem (unl)                                                  //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[165]) begin : include_map165
Mapper165 map165(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[165]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	.m2_inv     (cpu_ce),
	.paused     (paused)
);
end else begin : omit_map165

end endgenerate

//*****************************************************************************//
// Name   : Magic Floor                                                        //
// Mappers: 218                                                                //
// Status : Working                                                            //
// Notes  : Appears unused in modern packs?                                    //
// Games  : Magic Floor                                                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[218]) begin : include_map218
Mapper218 map218(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[218]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
	// savestates              
	// savestates support - but no state in mapper needs saving
);
end else begin : omit_map218

end endgenerate

//*****************************************************************************//
// Name   : Mapper 227                                                 //
// Mappers: 227                                                                //
// Status : Needs evaluation                                                   //
// Notes  :                                                                    //
// Games  : 1200-in-1, 600-in-1, Bio Hazard                                    //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[227]) begin : include_map227
Mapper227 map227(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[227]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map227

end endgenerate

//*****************************************************************************//
// Name   : Active Enterprises                                                 //
// Mappers: 228                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Cheetamen                                                          //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[228]) begin : include_map228
Mapper228 map228(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[228]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map228

end endgenerate

//*****************************************************************************//
// Name   : Maxi 15                                                            //
// Mappers: 234                                                                //
// Status : Needs Evaluation                                                   //
// Notes  : The fact that this mapper needs a different cpu data in concerns me//
//          either this indicates the mapper is not correctly written or that  //
//          the system itself is not behaving correctly.                       //
// Games  : Maxi-15 Pack (unl)                                                 //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[234]) begin : include_map234
Mapper234 map234(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[234]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_from_ram),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map234

end endgenerate

//*****************************************************************************//
// Name   : Mapper 246                                                         //
// Mappers: 246                                                                 //
// Status : Needs evaluation                                                   //
// Notes  :                                                                    //
// Games  : Feng Shen Bang                                                     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[246]) begin : include_map246
Mapper246 map246(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[246]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map246

end endgenerate

//*****************************************************************************//
// Name   : RAMBO1 (Tengen MMC3)                                               //
// Mappers: 64, 158                                                            //
// Status : Needs testing.  Irq might be slightly off.                         //
// Notes  : Consider merging with MMC3                                         //
// Games  : Rolling Thunder, Klax, Skull and Crossbones, Alien Syndrome (158)  //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[64] | POCKET_MAPPER_MASK[158]) begin : include_rambo1
Rambo1 rambo1(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[64] | me[158]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[24])
);
end else begin : omit_rambo1
assign SaveStateBus_wired_or[24] = '0;
end endgenerate

//*****************************************************************************//
// Name   : NesEvent                                                           //
// Mappers: 105                                                                //
// Status : Working                                                            //
// Notes  : This wraps the MMC1 mapper, consider merging more elegantly        //
// Games  : Nintendo World Championships 1990 (start hack)                     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[105]) begin : include_nesev
NesEvent nesev(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[105]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_nesev

end endgenerate


//*****************************************************************************//
// Name   : Konami VRC-1                                                       //
// Mappers: 75                                                                 //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : King Kong 2, Exciting Boxing, Tetsuwan Atom                        //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[75]) begin : include_vrc1
VRC1 vrc1(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[75]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[18])
);
end else begin : omit_vrc1
assign SaveStateBus_wired_or[18] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Konami VRC-3                                                       //
// Mappers: 73                                                                 //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Salamander (j)                                                     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[73]) begin : include_vrc3
VRC3 vrc3(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[73]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[19])
);
end else begin : omit_vrc3
assign SaveStateBus_wired_or[19] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Konami VRC2/4                                                      //
// Mappers: 21, 22, 23, 25, 27 (pirate of 23)                                  //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Wai Wai World 2, Twinbee 3, Contra (j), Gradius II (j)             //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[21] | POCKET_MAPPER_MASK[22] | POCKET_MAPPER_MASK[23] | POCKET_MAPPER_MASK[25] | POCKET_MAPPER_MASK[27]) begin : include_vrc24
VRC24 vrc24(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[21] | me[22] | me[23] | me[25] | me[27]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[9])
);
end else begin : omit_vrc24
assign SaveStateBus_wired_or[9] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Konami VRC5                                                        //
// Mappers: 547                                                                //
// Status : Needs Evaluation                                                   //
// Notes  :                                                                    //
// Games  : Konami Q-Ta (Space School and Space College (J))                   //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[547]) begin : include_vrc5
VRC5 vrc5(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[547]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_din    (chr_din),
	.chr_write  (chr_write),
	.chr_dout_b (chr_dout_b),
	.paused     (paused),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[36]),
	
	.Savestate_MAPRAMactive   (Savestate_MAPRAMactive),
	.Savestate_MAPRAMAddr     (Savestate_MAPRAMAddr[10:0]),     
	.Savestate_MAPRAMRdEn     (Savestate_MAPRAMRdEn),    
	.Savestate_MAPRAMWrEn     (Savestate_MAPRAMWrEn),    
	.Savestate_MAPRAMWriteData(Savestate_MAPRAMWriteData),
	.Savestate_MAPRAMReadData (SaveStateRAM_wired_or[2])
);
end else begin : omit_vrc5
assign SaveStateBus_wired_or[36] = '0;
assign SaveStateRAM_wired_or[2] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Konami VRC-6                                                       //
// Mappers: 24, 26                                                             //
// Status : Working. Audio needs evaluation. Startup instability.              //
// Notes  : External audio needs to be mixed correctly.                        //
// Games  : Akamajou Densetsu, Esper Dream 2, Mouryou Senki Madara             //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[24] | POCKET_MAPPER_MASK[26]) begin : include_vrc6
VRC6 vrc6(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[24] | me[26]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (vrc6_audio),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[10])
);
end else begin : omit_vrc6
assign SaveStateBus_wired_or[10] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Konami VRC-7                                                       //
// Mappers: 85                                                                 //
// Status : Working.                                                           //
// Notes  : Audio mixing needs evaluation                                      //
// Games  : Lagrange Point, Tiny Toon Aventures 2 (j)                          //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[85]) begin : include_vrc7
VRC7 vrc7(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[85]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (vrc7_audio),
	.audio_b    (audio_out_b)
);
end else begin : omit_vrc7

end endgenerate

//*****************************************************************************//
// Name   : Namco 163                                                          //
// Mappers: 19, 210                                                            //
// Status : Needs Evaluation                                                   //
// Notes  : This mapper requires submappers for correct operation              //
// Games  : Digital Devil Story, Battle Fleet, Famista                         //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[19] | POCKET_MAPPER_MASK[210]) begin : include_n163
N163 n163(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[210] | me[19]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (n163_audio),
	.audio_b    (audio_out_b),
	// Special ports
	.audio_dout	(n163_data),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[14])
);
end else begin : omit_n163
assign SaveStateBus_wired_or[14] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Waixing 162                                                        //
// Mappers: 162                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Zelda - San Shen Zhi Li                                            //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[162]) begin : include_map162
Mapper162 map162(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[162]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map162

end endgenerate

//*****************************************************************************//
// Name   : Nanjing 163                                                        //
// Mappers: 163                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Final Fantasy VII (163), Pokemon Yellow (163)                      //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[163]) begin : include_map163
Nanjing map163(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[163]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special Ports
	.paused     (paused)
);
end else begin : omit_map163

end endgenerate


//*****************************************************************************//
// Name   : Waixing 164                                                        //
// Mappers: 164                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Final Fantasy V                                                    //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[164]) begin : include_map164
Mapper164 map164(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[164]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map164

end endgenerate

//*****************************************************************************//
// Name   : DIS23C01 DAOU ROM CONTROLLER, Korea                                //
// Mappers: 156                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Metal Force (K), Buzz and Waldog (K), General's Son (K),           //
//          Koko Adventure (K)                                                 //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[156]) begin : include_daou
Mapper156 daou(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[156]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[37])
);
end else begin : omit_daou
assign SaveStateBus_wired_or[37] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sachen 8259                                                        //
// Mappers: 137, 138, 139, 141, 150, 243                                       //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : The Great Wall (137), Silver Eagle (138), Hell Fighter (139),      //
//          Super Cart 6 - 6 in 1(141), Strategist (150), Poker III (243)      //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[137] | POCKET_MAPPER_MASK[138] | POCKET_MAPPER_MASK[139] | POCKET_MAPPER_MASK[141] | POCKET_MAPPER_MASK[150] | POCKET_MAPPER_MASK[243]) begin : include_sachen
Sachen8259 sachen(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[137] | me[138] | me[139] | me[141] | me[150] | me[243]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[22])
);
end else begin : omit_sachen
assign SaveStateBus_wired_or[22] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sachen JV001                                                       //
// Mappers: 136, 147, 132, 173, 172, 36                                        //
// Status : Working                                                            //
// Notes  : 147 only tested with 60 pin version                                //
// Games  : Wei Lai Xiao Zi (136), Chinese Kungfu (147), Creatom (132),        //
//          F-15 City War (173), Mahjong Block (172), Strike Wolf (36)         //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[36] | POCKET_MAPPER_MASK[132] | POCKET_MAPPER_MASK[136] | POCKET_MAPPER_MASK[147] | POCKET_MAPPER_MASK[172] | POCKET_MAPPER_MASK[173]) begin : include_sachenj
SachenJV001 sachenj(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[136] | me[147] | me[132] | me[173] | me[172] | me[36]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[23])
);
end else begin : omit_sachenj
assign SaveStateBus_wired_or[23] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Sachen NROM                                                        //
// Mappers: 143                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Dancing Blocks, Magical Mathematics                                //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[143]) begin : include_sachenn
SachenNROM sachenn(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[143]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
	// savestates              
	// savestates support - but no state in mapper needs saving
);
end else begin : omit_sachenn

end endgenerate

//*****************************************************************************//
// Name   : JY Company                                                         //
// Mappers: 90, 209, 211, 35                                                   //
// Status : Working (needs testing)                                            //
// Notes  : 211 and 35 can be considered duplicates.                           //
// Games  : Aladdin (90), Power Rangers 3 (209), Warioland II (35),            //
//          Tiny Toon Adventures 6 (211)                                       //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[35] | POCKET_MAPPER_MASK[90] | POCKET_MAPPER_MASK[209] | POCKET_MAPPER_MASK[211]) begin : include_jycompany
JYCompany jycompany(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[90] | me[209] | me[211] | me[35]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.paused     (paused),
	.chr_ain_o  (chr_ain_orig),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[35])
);
end else begin : omit_jycompany
assign SaveStateBus_wired_or[35] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 91                                                          //
// Mappers: 91                                                                 //
// Status : Working (Needs testing)                                            //
// Notes  :                                                                    //
// Games  : Street Fighter 3, Mortal Kombat II, Dragon Ball Z 2,               //
//          Mario & Sonic 2,  Mario Rider,                                     //
//          1995 Super HIK 4-in-1 (JY-016), 1995 Super HiK 4-in-1 (JY-017)     //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[91]) begin : include_map91
Mapper91 map91(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[91]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	.chr_ain_o  (chr_ain_orig)
);
end else begin : omit_map91

end endgenerate

//*****************************************************************************//
// Name   : Mapper 225                                                         //
// Mappers: 225, 255                                                           //
// Status : Working                                                            //
// Notes  : Defining 225 as with 74'670 (4-nybble RAM) and 255 as without      //
// Games  : 64-in-1 (225), 110-in-1 (255 - with glitched menu selection)       //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[225] | POCKET_MAPPER_MASK[255]) begin : include_map225
Mapper225 map225(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[225] | me[255]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map225

end endgenerate

//*****************************************************************************//
// Name   : Mapper 200                                                         //
// Mappers: 200, 212                                                           //
// Status : Working                                                            //
// Notes  : Simple address-latch multicart (NROM-128 style)                    //
// Games  : 36-in-1                                                            //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[200] | POCKET_MAPPER_MASK[212]) begin : include_map200
Mapper200 map200(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[200] | me[212]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b)
);
end else begin : omit_map200

end endgenerate

//*****************************************************************************//
// Name   : AVE NINA-08                                                        //
// Mappers: 487                                                                //
// Status : Working                                                            //
// Notes  : 30-in-1 multicart supporting NINA-03 and Color Dreams games        //
// Games  : (Unreleased Maxivision 30-in-1 multicart)                          //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[487]) begin : include_map487
Mapper487 map487(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[487]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ),
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[39])
);
end else begin : omit_map487
assign SaveStateBus_wired_or[39] = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 413                                                         //
// Mappers: 413                                                                //
// Status : Working                                                            //
// Notes  :                                                                    //
// Games  : Super Russian Roulette                                             //
//*****************************************************************************//
generate if (POCKET_MAPPER_MASK[413]) begin : include_map413
Mapper413 map413 (
	.clk        (clk),
	.ce         (ce),
	.enable     (me[413]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_out_b),
	// Special ports
	.chr_ain_o  (chr_ain_orig),
	.prg_aoute  (prg_aoute_m413),
	.m2_inv     (cpu_ce),
	.paused     (paused)
);
end else begin : omit_map413
assign prg_aoute_m413 = '0;
end endgenerate

//*****************************************************************************//
// Name   : FDS                                                                //
// Mappers: 20                                                                 //
// Status : Audio good. Drive mechanics okay, but dated. Needs rewrite.        //
// Notes  : Uses a special wire to signal disk changes. Req. modified BIOS.    //
// Games  : Bio Miracle for audio, Various unlicensed games for compatibility. //
//*****************************************************************************//
tri0 [1:0] fds_diskside;
generate if (POCKET_MAPPER_MASK[20]) begin : include_mapfds
MapperFDS mapfds(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[20]),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (fds_audio),
	.audio_b    (audio_out_b),
	// Special ports
	.prg_dbus   (prg_from_ram),
	.audio_dout	(fds_data),
	.diskside_b (fds_diskside),
	.max_diskside (max_diskside),
	.fds_busy   (fds_busy),
	.fds_eject_btn (fds_eject),
	.fds_auto_eject_en (fds_auto_eject),
	.fds_fast   (fds_fast),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ),
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[38])
);
end else begin : omit_mapfds
assign SaveStateBus_wired_or[38] = '0;
assign fds_diskside = '0;
end endgenerate

//*****************************************************************************//
// Name   : Mapper 31                                                          //
// Mappers: 31 and NSF Player                                                  //
// Status : Testing                                                            //
// Notes  : Uses Mapper 31.15 (submapper) for NSF Player; NSF 1.0 only         //
// Games  : Famicompo Pico 2014, NSF 1.0                                       //
//*****************************************************************************//
wire [5:0] exp_audioe;
generate if (POCKET_MAPPER_MASK[31]) begin : include_nsfplayer
NSF nsfplayer(
	.clk        (clk),
	.ce         (ce),
	.enable     (me[31]),
	.flags      ({flags[31:25], 4'd0, flags[20:0]}),
	.prg_ain    (prg_ain),
	.prg_aout_b (prg_addr_b),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (chr_addr_b),
	.chr_read   (chr_read),
	.chr_dout_b (chr_dout_b), // Special port
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (irq_b),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.exp_audioe (exp_audioe),  // Expansion Enabled (0x0=None, 0x1=VRC6, 0x2=VRC7, 0x4=FDS, 0x8=MMC5, 0x10=N163, 0x20=SS5B
	.audio_b    (audio_out_b),
	// Special ports
	.chr_write  (chr_write),
	.fds_din    (fds_data)
);
end else begin : omit_nsfplayer
assign exp_audioe = '0;
end endgenerate

wire [15:0] ss5b_audio;
generate if (POCKET_MAPPER_MASK[69]) begin : include_snd_5bm
SS5b_mixed snd_5bm (
	.clk(clk),
	.ce(ce),
	.enable(me[69]),
	.wren(prg_write),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.audio_in(audio_in),
	.audio_out(ss5b_audio),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[13])
);
end else begin : omit_snd_5bm
assign SaveStateBus_wired_or[13] = '0;
assign ss5b_audio = '0;
end endgenerate

wire [15:0] n163_audio;
wire [7:0] n163_data;
generate if (POCKET_MAPPER_MASK[19]) begin : include_snd_n163
namco163_mixed snd_n163 (
	.clk(clk),
	.ce(ce),
	.submapper(flags[24:21]),
	.enable(me[19]),
	.wren(prg_write),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.data_out(n163_data),
	.audio_in(audio_in),
	.audio_out(n163_audio),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[15]),
	
	.Savestate_MAPRAMactive   (Savestate_MAPRAMactive),
	.Savestate_MAPRAMAddr     (Savestate_MAPRAMAddr[6:0]),     
	.Savestate_MAPRAMRdEn     (Savestate_MAPRAMRdEn),    
	.Savestate_MAPRAMWrEn     (Savestate_MAPRAMWrEn),    
	.Savestate_MAPRAMWriteData(Savestate_MAPRAMWriteData),
	.Savestate_MAPRAMReadData (SaveStateRAM_wired_or[0])
);
end else begin : omit_snd_n163
assign SaveStateBus_wired_or[15] = '0;
assign SaveStateRAM_wired_or[0] = '0;
assign n163_audio = '0;
assign n163_data = '0;
end endgenerate

wire [15:0] mmc5_audio;
wire [7:0] mmc5_data;
generate if (POCKET_MAPPER_MASK[5]) begin : include_snd_mmc5
mmc5_mixed snd_mmc5 (
	.clk(clk),
	.ce(ce),
	.enable(me[5]),
	.wren(prg_write),
	.rden(prg_read),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.data_out(mmc5_data),
	.audio_in(audio_in),
	.audio_out(mmc5_audio),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[17])
);
end else begin : omit_snd_mmc5
assign SaveStateBus_wired_or[17] = '0;
assign mmc5_audio = '0;
assign mmc5_data = '0;
end endgenerate

wire [15:0] fds_audio;
wire [7:0] fds_data;
generate if (POCKET_MAPPER_MASK[20]) begin : include_snd_fds
fds_mixed snd_fds (
	.clk(clk),
	.ce(ce),
	.enable(me[20]),
	.wren(prg_write),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.data_out(fds_data),
	.audio_in(audio_in),
	.audio_out(fds_audio),
	// savestates
	.Savestate_MAPRAMactive   (Savestate_MAPRAMactive),
	.Savestate_MAPRAMAddr     (Savestate_MAPRAMAddr[7:0]),
	.Savestate_MAPRAMRdEn     (Savestate_MAPRAMRdEn),
	.Savestate_MAPRAMWrEn     (Savestate_MAPRAMWrEn),
	.Savestate_MAPRAMWriteData(Savestate_MAPRAMWriteData),
	.Savestate_MAPRAMReadData (SaveStateRAM_wired_or[3])
);
end else begin : omit_snd_fds
assign SaveStateRAM_wired_or[3] = '0;
assign fds_audio = '0;
assign fds_data = '0;
end endgenerate

wire [15:0] vrc7_audio;
generate if (POCKET_MAPPER_MASK[85]) begin : include_snd_vrc7
vrc7_mixed snd_vrc7 (
	.clk(clk),
	.ce(ce),
	.enable(me[85]),
	.wren(prg_write),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.audio_in(audio_in),
	.audio_out(vrc7_audio)
);
end else begin : omit_snd_vrc7
assign vrc7_audio = '0;
end endgenerate

wire [15:0] vrc6_audio;
generate if (POCKET_MAPPER_MASK[24] | POCKET_MAPPER_MASK[26]) begin : include_snd_vrc6
vrc6_mixed snd_vrc6 (
	.clk(clk),
	.ce(ce),
	.enable(me[24] | me[26]),
	.wren(prg_write),
	.addr_invert(me[26]),
	.addr_in(prg_ain),
	.data_in(prg_din),
	.audio_in(audio_in),
	.audio_out(vrc6_audio),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[11])
);
end else begin : omit_snd_vrc6
assign SaveStateBus_wired_or[11] = '0;
assign vrc6_audio = '0;
end endgenerate


`include "mapper_config.vh"
reg [1023:0] me;

always @* begin
	me = 1024'd0;
	me[{flags[18:17],flags[7:0]}] = POCKET_MAPPER_MASK[{flags[18:17],flags[7:0]}];

	// Mapper output to cart pins
	{prg_aout[21:0], prg_allow,   chr_aout,   vram_a10,   vram_ce,   chr_allow,   prg_dout,   chr_dout,   irq,   audio} =
	{prg_addr_b,     prg_allow_b, chr_addr_b, vram_a10_b, vram_ce_b, chr_allow_b, prg_dout_b, chr_dout_b, irq_b, audio_out_b};

	// Currently only used for Mapper 16 EEPROM. Expand if needed.
	{mapper_addr, mapper_data_out, mapper_prg_write, mapper_ovr} = (me[159] | me[16]) ?
		{map16_mapper_addr, map16_data_out, map16_prg_write, map16_ovr} : 28'd0;
		
	// Currently only used for Mapper 413 Misc ROM. Expand if needed.
	prg_aout[24:22] = me[413] ? prg_aoute_m413 : 3'd0;

	{diskside} = {fds_diskside};

	// Behavior helper flags
	has_chr_dout    = flags_out_b[0];
	prg_bus_write   = flags_out_b[1];
	prg_conflict    = flags_out_b[2];
	has_savestate   = flags_out_b[3];
	prg_conflict_d0 = flags_out_b[4];
	has_flashsaves  = flags_out_b[5];

	// Address translation for SDRAM
	if ((prg_aout[21] == 1'b0) && (prg_aout[24] == 1'b0))
		prg_aout[20:0] = {(prg_aout[20:11] & prg_mask[9:0]), prg_aout[10:0]};

	if (chr_aout[21:20] == 2'b10)
		chr_aout[19:0] = {(chr_aout[19:11] & chr_mask[8:0]), chr_aout[10:0]};


	// Remap the CHR address into VRAM, if needed.
	chr_aout = vram_ce ? {11'b11_1010_0000_0, vram_a10, chr_ain[9:0]} : chr_aout;
	prg_aout = (prg_ain < 'h2000) ? {11'b11_1000_0000_0, prg_ain[10:0]} : prg_aout;
	prg_allow = prg_allow || (prg_ain < 'h2000);

	// The motherboard memories take priority over mapper-local RAM and
	// nametable wiring only while Vs. mode is selected. Explicitly suppress
	// mapper bus overrides so reads come from the selected SDRAM regions.
	if (vs_prg_ram) begin
		prg_aout = {3'b000, vs_prg_ram_addr};
		prg_allow = 1'b1;
		prg_bus_write = 1'b0;
		prg_conflict = 1'b0;
		prg_conflict_d0 = 1'b0;
	end

	if (vs_nametable_ram) begin
		chr_aout = vs_nametable_ram_addr;
		chr_allow = 1'b1;
		vram_ce = 1'b0;
		has_chr_dout = 1'b0;
	end
end

// savestates
localparam SAVESTATE_MODULES    = 41;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];

assign SaveStateBus_Dout  = SaveStateBus_wired_or[ 0] | SaveStateBus_wired_or[ 1] | SaveStateBus_wired_or[ 2] | SaveStateBus_wired_or[ 3] | SaveStateBus_wired_or[ 4] |
									  SaveStateBus_wired_or[ 5] | SaveStateBus_wired_or[ 6] | SaveStateBus_wired_or[ 7] | SaveStateBus_wired_or[ 8] | SaveStateBus_wired_or[ 9] |
									 SaveStateBus_wired_or[10] | SaveStateBus_wired_or[11] | SaveStateBus_wired_or[12] | SaveStateBus_wired_or[13] | SaveStateBus_wired_or[14] |
									 SaveStateBus_wired_or[15] | SaveStateBus_wired_or[16] | SaveStateBus_wired_or[17] | SaveStateBus_wired_or[18] | SaveStateBus_wired_or[19] |
									  SaveStateBus_wired_or[20] | SaveStateBus_wired_or[21] | SaveStateBus_wired_or[22] | SaveStateBus_wired_or[23] | SaveStateBus_wired_or[24] |
									  SaveStateBus_wired_or[25] | SaveStateBus_wired_or[26] | SaveStateBus_wired_or[27] | SaveStateBus_wired_or[28] | SaveStateBus_wired_or[29] |
									  SaveStateBus_wired_or[30] | SaveStateBus_wired_or[31] | SaveStateBus_wired_or[32] | SaveStateBus_wired_or[33] | SaveStateBus_wired_or[34] |
									  SaveStateBus_wired_or[35] | SaveStateBus_wired_or[36] | SaveStateBus_wired_or[37] | SaveStateBus_wired_or[38] | SaveStateBus_wired_or[39] |
									  SaveStateBus_wired_or[40];

localparam SAVESTATERAM_MODULES    = 4;
wire [7:0] SaveStateRAM_wired_or[0:SAVESTATERAM_MODULES-1];
assign Savestate_MAPRAMReadData = SaveStateRAM_wired_or[0] | SaveStateRAM_wired_or[1] | SaveStateRAM_wired_or[2] | SaveStateRAM_wired_or[3];

endmodule
