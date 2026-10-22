"""Prepare simulations with controller-port instances extracted from actual RTL."""
import argparse
from pathlib import Path
import re

parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=True)
source=args.source
core=(source/'target/pocket/core_top.v').read_text()
blocks=[]
for module,name in [('data_loader','save_data_loader'),('data_unloader','save_data_unloader')]:
    match=re.search(r'  '+module+r' #\(.*?\n  \) '+name+r' \(.*?\n  \);',core,re.S)
    # The non-greedy prefix can include preceding instances. Keep the final start.
    starts=list(re.finditer(r'  '+module+r' #\(',match[0]))
    blocks.append(match[0][starts[-1].start():])
wrapper='''module save_bridge_ports(input clk_74a,clk_85_9,clk_ppu_21_47,
input bridge_wr,bridge_rd,bridge_endian_little,input [31:0] bridge_addr,bridge_wr_data,
output [31:0] sd_read_data,output sd_buff_wr,sd_buff_rd,
output [18:0] sd_buff_addr,output [7:0] sd_buff_dout,input [7:0] sd_buff_din,
input save_busy,output save_wr,save_rd,
input save_transfer_active,save_transfer_loading,downloading,loader_busy,
input clearing_ram,sleep_savestate,corepaused,ppu_read,cpu_read,
output save_memory_owned,save_memory_ready,ppu_memory_read,cpu_memory_read);
wire [18:0] sd_buff_addr_in,sd_buff_addr_out;
assign sd_buff_addr=sd_buff_wr ? sd_buff_addr_in : sd_buff_addr_out;
'''+ '\n'.join(blocks)+'\n'
nes=(source/'rtl/nes_top.sv').read_text()
for signal in ['save_wr','save_rd']:
    expression=re.search(r'wire '+signal+r' = ([^;]+);',nes)[1]
    wrapper+='assign '+signal+' = '+expression+';\n'
ownership=re.search(r'  wire save_memory_owned = .*?  assign save_memory_ready = [^;]+;',nes,re.S)
if ownership:
    wrapper+=ownership[0].replace('wire save_memory_owned =','assign save_memory_owned =')+'\n'
    for channel,signal in [('ch0','ppu_memory_read'),('ch1','cpu_memory_read')]:
        expression=re.search(r'\.'+channel+r'_rd\s*\((.*?)\),',nes)[1]
        wrapper+='assign '+signal+' = '+expression+';\n'
else:
    wrapper+='assign save_memory_owned=0, save_memory_ready=1;\n'
    wrapper+='assign ppu_memory_read=ppu_read, cpu_memory_read=cpu_read;\n'
wrapper+='endmodule\n'
(args.out/'save_bridge_ports.sv').write_text(wrapper)
(args.out/'save_state_controller.sv').write_text((source/'target/pocket/save_state_controller.sv').read_text())
for filename in ['data_loader.sv','data_unloader.sv']:
    (args.out/filename).write_text((source/'target/pocket'/filename).read_text())
sdram=(source/'rtl/upstream/sdram.sv').read_text()
# Verilator cannot simulate the procedural bidirectional pin driver. Split
# the input/output pins in this simulation copy; command/address logic stays.
sdram=sdram.replace('inout  reg [15:0] SDRAM_DQ,','input [15:0] SDRAM_DQ_in, output reg [15:0] SDRAM_DQ_out,')
sdram=sdram.replace("SDRAM_DQ <= 'Z;", "SDRAM_DQ_out <= 0;")
sdram=sdram.replace('SDRAM_nWE, SDRAM_DQ}', 'SDRAM_nWE, SDRAM_DQ_out}')
sdram=sdram.replace('data_reg <= SDRAM_DQ;', 'data_reg <= SDRAM_DQ_in;')
sdram=sdram.replace('reg [4:0] reset=5\'h1f;', 'reg [4:0] reset=5\'h1f;\nreg init_old=0;')
sdram=sdram.replace('\treg init_old=0;\n','')
(args.out/'sdram.sv').write_text(sdram)
# The real synchronizers and transfer controller are used by the guarded test.
common=(source/'platform/pocket/common.v').read_text()
sync=re.search(r'module synch_3\b.*?endmodule',common,re.S)[0]
(args.out/'synch_3.v').write_text(sync+'\n')
transfer=source/'target/pocket/save_transfer_controller.sv'
if transfer.exists():
    (args.out/'save_transfer_controller.sv').write_text(transfer.read_text())
print(args.out)
