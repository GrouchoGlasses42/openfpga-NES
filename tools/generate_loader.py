#!/usr/bin/env python3
"""Generate Chip32 routing from the same mapper inventory used for hardware."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / "mapper_manifest.json").read_text())
    source = '''architecture chip32.vm
// Error and normal entry vectors. All instructions precede string data.
jp io_error
jp main

main:
  ld r6,#0
  ld r0,#0
  ld r1,#0x1b00
  getext r0,r1
  ld r2,#fds_extension
  test r1,r2
  jp z,load_fds
  ld r2,#nes_extension
  test r1,r2
  jp z,read_nes_header
  ld r2,#fc_extension
  test r1,r2
  jp nz,bad_header
read_nes_header:
  open r0,r1
  jp nz,io_error
  ld r2,#0x1a00
  ld r3,#16
  read r2,r3
  jp nz,io_error
  close
  ld.l r1,(0x1a00)
  cmp r1,#0x1a53454e
  jp nz,bad_header
  ld.b r1,(0x1a06)
  bit r1,#4
  jp nz,bad_header
  ld r4,r1
  and r4,#0xf0
  lsr r4,#4
  ld.b r2,(0x1a07)
  ld r3,r2
  and r3,#0xf0
  or r4,r3
  and r2,#0x0c
  cmp r2,#8
  jp nz,check_dirty_header
  // NES 2.0 extended mapper ID. Hardware upstream currently uses ten bits.
  ld.b r3,(0x1a08)
  and r3,#15
  asl r3,#8
  or r4,r3
  jp dispatch

check_dirty_header:
  // Match upstream GameLoader's treatment of dirty iNES 1.0 headers.
  ld.b r2,(0x1a09)
  and r2,#0xfe
  ld.w r3,(0x1a0a)
  or r2,r3
  ld.w r3,(0x1a0c)
  or r2,r3
  ld.w r3,(0x1a0e)
  or r2,r3
  cmp r2,#0
  jp z,dispatch
  and r4,#15

dispatch:
'''
    for variant in manifest["variants"]:
        if variant["name"] == "fds":
            continue
        for mapper in variant["mappers"]:
            source += f"  cmp r4,#{mapper}\n  jp z,select_{variant['name']}\n"
    source += "  jp unsupported\n"
    for variant in manifest["variants"]:
        if variant["name"] == "fds":
            continue
        source += f"\nselect_{variant['name']}:\n  ld r0,#{variant['id']}\n  core r0\n  jp load_content\n"
    fds_id = next(v["id"] for v in manifest["variants"] if v["name"] == "fds")
    source += f'''
load_fds:
  ld r6,#1
  // Validate one to four 65,500-byte sides, with optional 16-byte FDS header.
  ld r0,#0
  open r0,r1
  jp nz,io_error
  ld r2,#0x1a00
  ld r3,#16
  read r2,r3
  jp nz,io_error
  close
  ld.l r2,(0x1a00)
  cmp r2,#0x1a534446
  jp nz,fds_length
  sub r1,#16
fds_length:
  ld r4,r1
  ld r5,#65500
  div r4,r5
  cmp r5,#0
  jp nz,bad_fds
  cmp r4,#1
  jp z,fds_bios
  cmp r4,#2
  jp z,fds_bios
  cmp r4,#3
  jp z,fds_bios
  cmp r4,#4
  jp nz,bad_fds
fds_bios:
  ld r0,#1
  open r0,r1
  jp nz,bad_bios
  close
  cmp r1,#8192
  jp nz,bad_bios
  ld r0,#{fds_id}
  core r0
  // BIOS RAM is separate from the disk loader and selected by bridge address.
  ld r0,#1
  loadf r0
  jp nz,bad_bios

load_content:
  ld r0,#0
  loadf r0
  jp nz,io_error
  ld r0,#11
  queryslot r0
  jp nz,load_save
  loadf r0
  jp nz,io_error
load_save:
  ld r0,#10
  queryslot r0
  jp nz,finish
  cmp r6,#0
  jp z,copy_save
  // A disk save replaces the disk RAM, including its 16-byte reserved prefix.
  // Reject an obviously damaged save before overwriting the clean disk image.
  open r0,r1
  jp nz,io_error
  ld r7,r1
  ld r8,#1
  cmp r1,#262144
  jp nz,bad_save_close
  ld r2,#0x1a00
  ld r3,#32
  ld r8,#2
  read r2,r3
  jp nz,bad_save_close
  close
  ld r8,#3
  ld.l r1,(0x1a10)
  cmp r1,#0x494e2a01
  jp nz,bad_save
  ld r8,#4
  ld.l r1,(0x1a14)
  cmp r1,#0x4e45544e
  jp nz,bad_save
  ld r8,#5
  ld.l r1,(0x1a18)
  cmp r1,#0x482d4f44
  jp nz,bad_save
  ld r8,#6
  ld.w r1,(0x1a1c)
  cmp r1,#0x4356
  jp nz,bad_save
  ld r8,#7
  ld.b r1,(0x1a1e)
  cmp r1,#0x2a
  jp nz,bad_save
copy_save:
  ld r0,#10
  loadf r0
  jp nz,io_error
finish:
  ld r0,#0x4002
  host r0,r0
  exit 0

unsupported:
  ld r0,#unsupported_message
  printf r0
  hex.w r4
  exit 1
bad_header:
  ld r0,#header_message
  printf r0
  exit 1
bad_fds:
  ld r0,#fds_message
  printf r0
  exit 1
bad_bios:
  ld r0,#bios_message
  printf r0
  exit 1
io_error:
  ld r0,#io_message
  printf r0
  exit 1
bad_save_close:
  close
bad_save:
  ld r9,r1
  ld r0,#save_message
  printf r0
  hex.b r8
  ld r0,#save_size_message
  printf r0
  hex.l r7
  ld r0,#save_value_message
  printf r0
  hex.l r9
  ld r0,#10
  ld r2,#0x1b00
  getname r0,r2
  ld r0,#save_file_message
  printf r0
  printf r2
  exit 1

fds_extension:
  db "FDS",0
nes_extension:
  db "NES",0
fc_extension:
  db "FC",0
unsupported_message:
  db "Unsupported mapper: 0x",0
header_message:
  db "Choose a valid NES ROM without a trainer, or an FDS disk image.",0
fds_message:
  db "FDS image must contain one to four complete 65500-byte disk sides.",0
bios_message:
  db "An 8192-byte fds.bios is required in Assets/nes/common.",0
io_message:
  db "Could not read the selected file.",0
save_message:
  db "FDS save rejected. Check ",0
save_size_message:
  db " Size ",0
save_value_message:
  db " Value ",0
save_file_message:
  db " File ",0
'''
    (ROOT / "chip32").mkdir(exist_ok=True)
    (ROOT / "chip32/loader.asm").write_text(source)
    print("Generated mapper routing, NES 2.0 handling and FDS BIOS loading")


if __name__ == "__main__":
    main()
