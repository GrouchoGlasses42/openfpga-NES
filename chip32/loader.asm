architecture chip32.vm
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
  cmp r4,#0
  jp z,select_standard
  cmp r4,#1
  jp z,select_standard
  cmp r4,#2
  jp z,select_standard
  cmp r4,#3
  jp z,select_standard
  cmp r4,#4
  jp z,select_standard
  cmp r4,#7
  jp z,select_standard
  cmp r4,#9
  jp z,select_standard
  cmp r4,#10
  jp z,select_standard
  cmp r4,#11
  jp z,select_standard
  cmp r4,#28
  jp z,select_standard
  cmp r4,#30
  jp z,select_standard
  cmp r4,#33
  jp z,select_standard
  cmp r4,#34
  jp z,select_standard
  cmp r4,#37
  jp z,select_standard
  cmp r4,#38
  jp z,select_standard
  cmp r4,#45
  jp z,select_standard
  cmp r4,#46
  jp z,select_standard
  cmp r4,#47
  jp z,select_standard
  cmp r4,#48
  jp z,select_standard
  cmp r4,#52
  jp z,select_standard
  cmp r4,#66
  jp z,select_standard
  cmp r4,#74
  jp z,select_standard
  cmp r4,#76
  jp z,select_standard
  cmp r4,#80
  jp z,select_standard
  cmp r4,#82
  jp z,select_standard
  cmp r4,#86
  jp z,select_standard
  cmp r4,#87
  jp z,select_standard
  cmp r4,#88
  jp z,select_standard
  cmp r4,#94
  jp z,select_standard
  cmp r4,#95
  jp z,select_standard
  cmp r4,#97
  jp z,select_standard
  cmp r4,#101
  jp z,select_standard
  cmp r4,#105
  jp z,select_standard
  cmp r4,#112
  jp z,select_standard
  cmp r4,#118
  jp z,select_standard
  cmp r4,#119
  jp z,select_standard
  cmp r4,#140
  jp z,select_standard
  cmp r4,#144
  jp z,select_standard
  cmp r4,#145
  jp z,select_standard
  cmp r4,#149
  jp z,select_standard
  cmp r4,#154
  jp z,select_standard
  cmp r4,#155
  jp z,select_standard
  cmp r4,#171
  jp z,select_standard
  cmp r4,#180
  jp z,select_standard
  cmp r4,#185
  jp z,select_standard
  cmp r4,#189
  jp z,select_standard
  cmp r4,#191
  jp z,select_standard
  cmp r4,#192
  jp z,select_standard
  cmp r4,#194
  jp z,select_standard
  cmp r4,#195
  jp z,select_standard
  cmp r4,#196
  jp z,select_standard
  cmp r4,#205
  jp z,select_standard
  cmp r4,#206
  jp z,select_standard
  cmp r4,#207
  jp z,select_standard
  cmp r4,#208
  jp z,select_standard
  cmp r4,#268
  jp z,select_standard
  cmp r4,#13
  jp z,select_discrete
  cmp r4,#15
  jp z,select_discrete
  cmp r4,#16
  jp z,select_discrete
  cmp r4,#18
  jp z,select_discrete
  cmp r4,#31
  jp z,select_discrete
  cmp r4,#32
  jp z,select_discrete
  cmp r4,#40
  jp z,select_discrete
  cmp r4,#41
  jp z,select_discrete
  cmp r4,#42
  jp z,select_discrete
  cmp r4,#65
  jp z,select_discrete
  cmp r4,#67
  jp z,select_discrete
  cmp r4,#68
  jp z,select_discrete
  cmp r4,#70
  jp z,select_discrete
  cmp r4,#71
  jp z,select_discrete
  cmp r4,#72
  jp z,select_discrete
  cmp r4,#77
  jp z,select_discrete
  cmp r4,#78
  jp z,select_discrete
  cmp r4,#79
  jp z,select_discrete
  cmp r4,#81
  jp z,select_discrete
  cmp r4,#83
  jp z,select_discrete
  cmp r4,#89
  jp z,select_discrete
  cmp r4,#92
  jp z,select_discrete
  cmp r4,#93
  jp z,select_discrete
  cmp r4,#99
  jp z,select_discrete
  cmp r4,#107
  jp z,select_discrete
  cmp r4,#111
  jp z,select_discrete
  cmp r4,#113
  jp z,select_discrete
  cmp r4,#133
  jp z,select_discrete
  cmp r4,#146
  jp z,select_discrete
  cmp r4,#148
  jp z,select_discrete
  cmp r4,#152
  jp z,select_discrete
  cmp r4,#153
  jp z,select_discrete
  cmp r4,#159
  jp z,select_discrete
  cmp r4,#165
  jp z,select_discrete
  cmp r4,#184
  jp z,select_discrete
  cmp r4,#190
  jp z,select_discrete
  cmp r4,#200
  jp z,select_discrete
  cmp r4,#212
  jp z,select_discrete
  cmp r4,#218
  jp z,select_discrete
  cmp r4,#225
  jp z,select_discrete
  cmp r4,#227
  jp z,select_discrete
  cmp r4,#228
  jp z,select_discrete
  cmp r4,#232
  jp z,select_discrete
  cmp r4,#234
  jp z,select_discrete
  cmp r4,#246
  jp z,select_discrete
  cmp r4,#255
  jp z,select_discrete
  cmp r4,#413
  jp z,select_discrete
  cmp r4,#487
  jp z,select_discrete
  cmp r4,#21
  jp z,select_special
  cmp r4,#22
  jp z,select_special
  cmp r4,#23
  jp z,select_special
  cmp r4,#25
  jp z,select_special
  cmp r4,#27
  jp z,select_special
  cmp r4,#35
  jp z,select_special
  cmp r4,#36
  jp z,select_special
  cmp r4,#64
  jp z,select_special
  cmp r4,#73
  jp z,select_special
  cmp r4,#75
  jp z,select_special
  cmp r4,#90
  jp z,select_special
  cmp r4,#91
  jp z,select_special
  cmp r4,#132
  jp z,select_special
  cmp r4,#136
  jp z,select_special
  cmp r4,#137
  jp z,select_special
  cmp r4,#138
  jp z,select_special
  cmp r4,#139
  jp z,select_special
  cmp r4,#141
  jp z,select_special
  cmp r4,#142
  jp z,select_special
  cmp r4,#143
  jp z,select_special
  cmp r4,#147
  jp z,select_special
  cmp r4,#150
  jp z,select_special
  cmp r4,#156
  jp z,select_special
  cmp r4,#158
  jp z,select_special
  cmp r4,#162
  jp z,select_special
  cmp r4,#163
  jp z,select_special
  cmp r4,#164
  jp z,select_special
  cmp r4,#172
  jp z,select_special
  cmp r4,#173
  jp z,select_special
  cmp r4,#209
  jp z,select_special
  cmp r4,#211
  jp z,select_special
  cmp r4,#243
  jp z,select_special
  cmp r4,#5
  jp z,select_expansion
  cmp r4,#19
  jp z,select_expansion
  cmp r4,#24
  jp z,select_expansion
  cmp r4,#26
  jp z,select_expansion
  cmp r4,#69
  jp z,select_expansion
  cmp r4,#210
  jp z,select_expansion
  cmp r4,#547
  jp z,select_expansion
  cmp r4,#85
  jp z,select_vrc7
  jp unsupported

select_standard:
  ld r0,#0
  core r0
  jp load_content

select_discrete:
  ld r0,#1
  core r0
  jp load_content

select_special:
  ld r0,#2
  core r0
  jp load_content

select_expansion:
  ld r0,#3
  core r0
  jp load_content

select_vrc7:
  ld r0,#4
  core r0
  jp load_content

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
  ld r0,#5
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
