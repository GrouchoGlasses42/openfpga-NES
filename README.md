# NES_experimental for Analogue Pocket

NES_experimental is an openFPGA core for the Analogue Pocket.
It runs Nintendo Entertainment System (NES) and Famicom cartridge images.
It also runs Famicom Disk System (FDS) disk images.

The core uses the NES hardware design from MiSTer and the Pocket port from agg23.
This project is an independent derivative of those projects.

The version format is `UPSTREAM_VERSION+YYYYMMDD`.
The suffix gives the package build date in UTC.
The base version follows the latest published [agg23 release](https://github.com/agg23/openfpga-NES/releases/latest).

## Features

- 145 mapper IDs across six FPGA images.
- Automatic FPGA image selection through the Chip32 loader.
- Expansion audio, including VRC7 and FDS audio.
- FDS images with one to four disk sides.
- Automatic and manual FDS disk changes.
- Game saves, Pocket Memories, and sleep where the mapper permits these functions.
- Nine composite blend modes and six palette selections.
- Controller turbo, multitap, and a virtual Zapper.

A mapper controls cartridge memory and, in some games, expansion audio.
The [mapper list](https://github.com/GrouchoGlasses42/openfpga-NES/blob/main/mapper_manifest.json) gives the mapper IDs for each FPGA image.

The core uses NTSC timing.
PAL blend modes change only the video filter.
The core does not play NSF files.

### Additional mappers

The comparison uses the mapper selection in [agg23's published core](https://github.com/agg23/openfpga-NES/blob/1.0.1/rtl/cart.sv).
NES_experimental adds these 15 mapper IDs to that release.
The examples identify software for each mapper.
They are not a complete game compatibility test result.

| Mapper ID | Hardware or board | Example games or compilations |
|---|---|---|
| 20 | Nintendo FDS | Zelda no Densetsu: The Hyrule Fantasy; Metroid, FDS version |
| [31](https://www.nesdev.org/wiki/INES_Mapper_031) | Music compilation cartridge | Famicompo Pico cartridge compilations |
| [40](https://www.nesdev.org/wiki/INES_Mapper_040) | NTDEC 2722 | Super Mario Bros. 2 (Japan), LF36 cartridge conversion |
| [45](https://www.nesdev.org/wiki/INES_Mapper_045) | MMC3 multicart boards | Super New Year Cart 15-in-1 |
| [52](https://www.nesdev.org/wiki/INES_Mapper_052) | Realtec 8213 and related boards | [Super Mario 7-in-1](https://mamedev.emulab.it/etabeta/2009/10/) |
| [81](https://www.nesdev.org/wiki/INES_Mapper_081) | NTDEC N715021 | Super Gun |
| [99](https://www.nesdev.org/wiki/INES_Mapper_099) | Nintendo Vs. System cartridge logic | Vs. Super Mario Bros.; Vs. Gumshoe |
| [142](https://www.nesdev.org/wiki/INES_Mapper_142) | Kaiser KS202 | Super Mario Bros. 2 (Japan), Kaiser cartridge conversion |
| [144](https://www.nesdev.org/wiki/INES_Mapper_144) | American Game Cartridges board | [Death Race](https://forums.nesdev.org/viewtopic.php?t=4179) |
| [156](https://www.nesdev.org/wiki/INES_Mapper_156) | Daou Infosys DIS23C01 | Metal Force; Koko Adventure; General's Son |
| [200](https://github.com/sanni/cartreader/blob/master/Cart_Reader/NES.ino) | HN-02 / MG109 multicart boards | 36-in-1 |
| [205](https://github.com/sanni/cartreader/blob/master/Cart_Reader/NES.ino) | MMC3 multicart boards | JC-016-2 multicarts |
| [208](https://www.nesdev.org/wiki/INES_Mapper_208) | Gouder MMC3 variant | Street Fighter IV, Gouder version |
| [212](https://www.nesdev.org/wiki/INES_Mapper_212) | Discrete-logic multicart boards | Super HiK 300-in-1 |
| [487](https://www.nesdev.org/wiki/NES_2.0_Mapper_487) | American Video Entertainment NINA-08 | Maxivision 30-in-1, unreleased version |

A multicart contains more than one game on one cartridge.
Mapper 31 reads cartridge compilations, not NSF files.
Mapper 99 provides cartridge logic for Vs. System software.
Complete Vs. System compatibility also depends on the arcade hardware functions.

### Expansion audio

NES_experimental also adds VRC7 FM audio for **Lagrange Point**.
[agg23's core already has mapper 85](https://github.com/agg23/openfpga-NES/blob/1.0.1/README.md#expansion-audio), but its VRC7 FM audio is disabled.
VRC7 audio is an addition to existing mapper support.
It is not an additional mapper ID.

## Installation

### Requirements

- An Analogue Pocket with openFPGA firmware.
- A microSD card with an openFPGA directory structure.
- The complete NES_experimental release ZIP from this repository's **Releases** page.
- A game image in a format from the table below.
- An 8192-byte FDS BIOS file for FDS games.

The repository and release packages contain no game ROMs, test ROMs, BIOS dumps, or user saves.
Test programs are available from the external projects in the accuracy section.

### Install the core

1. Extract the release ZIP on your computer.
2. Copy the `Assets`, `Cores`, and `Platforms` directories to the microSD card root.
3. Merge each directory with the directory that is already on the card.
4. Put your game images in `Assets/nes/common`.
5. For FDS games, put the BIOS file in `Assets/nes/common`.
6. Name the BIOS file `fds.bios`.
7. Insert the microSD card into the Pocket.
8. Start **NES_experimental** from the **openFPGA** menu.
9. Select a game from the **Cartridge** browser.

The core directory is `Cores/groucho.NES_experimental`.
The BIOS file name and file size must be exact.

### File formats and locations

All paths in this table start at the microSD card root.

| Item | Format or requirement | Location |
|---|---|---|
| NES or Famicom cartridge | `.nes` or `.fc`, with an iNES or NES 2.0 header | `Assets/nes/common` |
| FDS disk | `.fds`, with or without a 16-byte FDS header | `Assets/nes/common` |
| FDS BIOS | `fds.bios`, exactly 8192 bytes | `Assets/nes/common` |
| Game saves | `.sav` or `.srm`, managed by Pocket OS | `Saves/nes/common` |

Each FDS side contains 65,500 bytes.
The loader accepts one to four sides.
The loader does not accept cartridge images without headers or cartridge images with trainers.

## Controls and settings

### Default controls

| Pocket control | NES function |
|---|---|
| D-pad | D-pad |
| A | A |
| B | B |
| Start | Start |
| Select | Select |
| X | A turbo |
| Y | B turbo |

**Turbo Speed** controls the turbo buttons.
Its default value is `0`, which sets turbo to Off.

### Video

**Core Settings** contains the video controls.
**Hide Overscan**, **Edge Masking**, and **Square Pixels** control the visible picture.
**Extra Sprites** increases the sprite limit and can change game behavior.

**Composite Blend** has these modes:

| Mode | Function |
|---|---|
| Off | No composite blend filter |
| Kitrinx Style | Blend adjacent pixels |
| NTSC Light | Light horizontal brightness and color filter |
| NTSC Medium | Medium horizontal brightness and color filter |
| NTSC Strong | Strong horizontal brightness and color filter |
| PAL Light | Light filter with color blend between scanlines |
| PAL Medium | Medium filter with color blend between scanlines |
| PAL Strong | Strong filter with color blend between scanlines |
| PAL Strong+ | Maximum PAL filter strength |

These filters approximate composite video color and brightness bandwidth.
They do not generate a composite video signal.
**Palette** selects the color palette independently of **Composite Blend**.

### FDS disks

**Disk Swap** has two settings:

| Setting | Function |
|---|---|
| Automatic | The core changes disk sides when the game requests a disk change. |
| Manual | **Eject / Change Disk** controls disk changes. |

Some games require manual disk changes.
**Fast Disk Access** decreases disk transfer delays.
Its default setting is Off.

### Game saves and Memories

A game save contains data that the game writes through its own save function.
A Memory contains a Pocket save state.
These are separate functions.

The core stores FDS changes in a game save file.
It does not change the original `.fds` file.

Memory and sleep functions depend on the mapper.
Pocket OS associates Memories and core settings with the core ID.
VRC7 games do not have Memory support.
The **No save support** message refers to save states.
The game's own save function is separate.

## Accuracy

Accuracy tests examine specific hardware functions.
A complete test result does not prove that every game or mapper operates correctly.
AccuracyCoin examines shared NES behavior.
FDS tests examine the disk hardware separately.

### Prepare the tests

1. Obtain the test files from the projects in the table below.
2. If a project supplies source only, build its ROM with the author's instructions.
3. Copy the test files to `Assets/nes/common/Tests` on the microSD card.
4. Set **Use Zapper** to Off.
5. Set **Use Multitap** to Off.
6. Set **Extra Sprites** to Off.
7. Set **Composite Blend** to Off.
8. Set **Turbo Speed** to `0`.
9. Set **Fast Disk Access** to Off.
10. Quit the core.
11. Start the core again before each test ROM.

The FDS tests require the same BIOS file as FDS games.
The test names below are the authors' file names.

| Test | Source | File |
|---|---|---|
| NES CPU and PPU tests | [AccuracyCoin by 100thCoin](https://github.com/100thCoin/AccuracyCoin) | `AccuracyCoin.nes` |
| FDS timer IRQ tests | [Sour's tests in nes-test-roms](https://github.com/christopherpow/nes-test-roms/tree/master/fdsirqtests) | `fdsirqtests.fds` |
| FDS mirroring | [FDS-Mirroring-Test by TakuikaNinja](https://github.com/TakuikaNinja/FDS-Mirroring-Test) | `mirroring-test.fds` |
| FDS audio reset | [FDS-Audio-Registers by TakuikaNinja](https://github.com/TakuikaNinja/FDS-Audio-Registers) | `audio-registers.fds` |
| FDS refresh watchdog | [FDS-4030D1-Addr by TakuikaNinja](https://github.com/TakuikaNinja/FDS-4030D1-Addr) | `4030d1-addr.fds` |
| FDS register viewer | [FDS-4023-Test by TakuikaNinja](https://github.com/TakuikaNinja/FDS-4023-Test) | `4023-test.fds` |

### Run AccuracyCoin

1. Open `AccuracyCoin.nes` from the **Cartridge** browser.
2. Use the D-pad to select the page heading at the top of the screen.
3. Press **Start** to run all tests.
4. Wait for the result table.
5. Record the pass, fail, and skip counts.

For the 146-test ROM, the target is **146 passes, zero failures, and zero skips**.
The five **DRAW** items display information and are not pass/fail tests.

**A** runs the selected test.
When the cursor is on a page heading, **A** runs all tests on that page.
**B** marks a test or page for omission.
An omitted test does not count as a pass.

AccuracyCoin uses the NROM mapper.
Its result does not test the banking, IRQ, audio, or save functions of every mapper.
A different mapper number in the ROM header does not give a valid test of that mapper.

### Run the FDS timer IRQ tests

1. Open `fdsirqtests.fds` from the **Cartridge** browser.
2. Wait for all 21 result rows.
3. Make sure that each row shows `O`.
4. Record any row that shows `X`.
5. Set **Fast Disk Access** to On.
6. Quit the core.
7. Start the core again.
8. Run the same test ROM again.
9. Make sure that all 21 rows show `O` again.
10. Set **Fast Disk Access** to Off after the test.

`O` means pass.
`X` means fail.
The numbers beside the results are IRQ counts.
A nonzero IRQ count does not mean failure.

### Run the FDS mirroring test

1. Open `mirroring-test.fds` from the **Cartridge** browser.
2. Wait for the three results.
3. Compare the results with this table.

| Test line | Expected result |
|---|---|
| `$4025.D3 W` | Pass |
| `$4030.D3 R` | Pass |
| `$4023.D0=0` | Pass |

### Run the FDS audio reset test

The top line shows the `$4023` setting in binary.
The first data row shows eight hexadecimal bytes, from `$4090` through `$4097`.
The second data row has no test function.

1. Open `audio-registers.fds` from the **Cartridge** browser.
2. Make sure that the top line shows `10000011`.
3. Press **A** to play a sound.
4. Press **B** to disable FDS audio.
5. Make sure that the top line shows `10000001`.
6. Make sure that the sound stops.
7. Compare the data row with the table below.
8. Press **B** to enable FDS audio again.
9. Press **A** to play the sound again.
10. Make sure that the sound plays.

| Position in the data row | Register | Expected value with audio disabled |
|---|---|---|
| First byte | `$4090`, volume gain | `40` |
| Second byte | `$4091`, wave phase | `00` |
| Eighth byte | `$4097`, modulation bias | `00` |

Other bytes depend on the audio state when you press **B**.
They do not have one fixed expected value.

### Run the FDS refresh watchdog test

1. Open `4030d1-addr.fds` from the **Cartridge** browser.
2. Wait for the two address fields.
3. Compare the addresses with this table.

| Field | Expected address |
|---|---|
| First address | `67FF` |
| Second address | `6E25` |

These values match the author's Twin Famicom reference capture.
These reference addresses use the Nintendo FDS BIOS.
A different BIOS can change the displayed addresses or font.
Horizontal raster bands are part of the display.
`XXXX` means that the test has not recorded a watchdog interrupt.
This program has no automatic Pass/Fail result.

### Use the FDS register viewer

This program displays registers from `$4020` through `$409F`.
It has no automatic Pass/Fail result.

1. Open `4023-test.fds` from the **Cartridge** browser.
2. Make sure that the top line shows `10000011`.
3. Press **A** to disable disk I/O.
4. Make sure that the top line shows `10000010`.
5. Press **A** to enable disk I/O again.
6. Press **B** to disable FDS audio.
7. Make sure that the top line shows `10000001`.
8. Press **B** to enable FDS audio again.

The displayed register values can change with disk and audio activity.
An exact match across the complete register display is not a pass condition.

### Test saves and sleep

This procedure requires a game with game saves and Memory support.

1. Start the game.
2. Make a game save.
3. Quit the core through Pocket OS.
4. Start the core again.
5. Open the same game file.
6. Make sure that the game save is present.
7. Create a new Memory through Pocket OS.
8. Change the game state.
9. Restore the Memory.
10. Make sure that the game returns to the saved state.
11. Put the Pocket into sleep.
12. Wake the Pocket.
13. Make sure that the game continues correctly.

### Report a test failure

The repository's **Issues** page accepts test reports.
A useful report contains these items:

- The core version and Pocket firmware version.
- The test ROM source, revision, and SHA-256 hash.
- The FDS BIOS SHA-256 hash, for an FDS test.
- The core settings and test steps.
- The expected result and the actual result.
- The test name, error code, or last test before a stop.
- A picture of the result screen, if available.

ROM files, BIOS dumps, and user saves are not required in a public test report.

## Build and source tests

### Tools

| Task | Tools |
|---|---|
| Configuration and loader tests | Python 3 |
| Chip32 loader assembly | [BASS with the Chip32 architecture](https://github.com/open-fpga/bass-chip32) |
| FPGA compilation | Quartus Prime Lite 21.1.1, build 850, with Cyclone V device files |
| HDL tests | Verilator, Icarus Verilog, and a C++ compiler |

The `generated/` directory contains configurations for all six FPGA images.
The release contains all six images because the loader selects an image for each mapper.

### Generate the configuration

1. Open a terminal in the repository root.
2. Run these commands.

```sh
python3 tools/configure_variant.py all
python3 tools/generate_loader.py
```

The second command writes `chip32/loader.asm`.
The repository also contains the assembled `loader.bin`.
A change to the loader source requires assembly before the loader tests.

The package build date is separate from the FPGA compilation date.
The version tool retains the upstream base version in `core.json`.

1. Set the package build date before a release.

```sh
python3 tools/stamp_version.py
```

### Compile an FPGA image

`tools/build.sh` takes one image name: `standard`, `discrete`, `special`, `expansion`, `vrc7`, or `fds`.
The script expects the repository at `/source` and a separate writable directory at `/build`.
The compiler results go to `/build/results`.

This example compiles the FDS image with the pinned Quartus container.

1. Start Docker.
2. Open a terminal in the repository root.
3. Run these commands.

```sh
mkdir -p ../build-results/fds
docker run --rm --platform linux/amd64 \
  --mount "type=bind,source=$PWD,target=/source,readonly" \
  --mount "type=bind,source=$(cd ../build-results/fds && pwd),target=/build" \
  ghcr.io/drizzt/quartus@sha256:b5b0f0b7af271a0b9e9adc0cad59ff773d8690742a1426500fd71056d2c09787 \
  bash /source/tools/build.sh fds
```

The release packager requires complete compiler results for all six images.
It rejects FPGA images that exceed device capacity or fail the reported timing requirements.

### Run source tests

The Python tests use synthetic data.
They do not require game ROMs, test ROMs, or a BIOS dump.

1. Open a terminal in the repository root.
2. Run the Python tests.

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The FDS bus tests use Verilator.
They do not require an FDS disk image or BIOS dump.

1. Run the FDS register test.

```sh
bash tools/run_fds_register_test.sh . /tmp/nes-fds-registers fixed
```

2. Run the FDS IRQ and watchdog test.

```sh
bash tools/run_fds_irq_bus_test.sh . /tmp/nes-fds-irq
```

3. Run the FDS audio reset test.

```sh
bash tools/run_fds_audio_reset_test.sh . /tmp/nes-fds-audio
```

4. Run the FDS state restoration test.

```sh
bash tools/run_fds_state_test.sh
```

HDL simulation does not test Pocket OS or the physical Pocket hardware.
Physical tests remain necessary for game saves, Memories, sleep, and the complete video and audio paths.

## Credits

| Contributor or project | Contribution |
|---|---|
| [Ludvig Strigeus](https://github.com/strigeus/fpganes) | Original FPGA NES design |
| [MiSTer NES contributors](https://github.com/MiSTer-devel/NES_MiSTer) | NES hardware, mappers, expansion audio, FDS, and save states |
| sorgelig, greyrogue, Kitrinx, and paulb-nl | Major contributions to the upstream NES core |
| [Adam Gastineau, agg23](https://github.com/agg23/openfpga-NES) | Analogue Pocket port and core integration |
| [OpenGateware contributors](https://github.com/opengateware) | Pocket platform components |
| [snckrz](https://github.com/snckrz/openfpga-NES-Analogizer) and Kitrinx | Composite blend filters |
| Kitrinx and Loopy | FDS audio implementation and hardware research |
| [T65 contributors](https://github.com/GrouchoGlasses42/openfpga-NES/blob/main/rtl/upstream/t65/T65.vhd) | CPU design, including work by Daniel Wallner, Mike Johnson, Wolfgang Scherr, and Morten Leikvoll |
| [100thCoin](https://github.com/100thCoin/AccuracyCoin) | AccuracyCoin |
| Sour | FDS IRQ tests |
| [TakuikaNinja](https://github.com/TakuikaNinja), SCSR, and paulb-nl | FDS diagnostics, hardware research, and refresh watchdog analysis |
| spiritualized1997 | Core icon |
| Kitrinx, FirebrandX, and NakedArthur | Color palettes |
| Analogue and [openFPGA contributors](https://github.com/open-fpga) | Pocket platform and Chip32 tools |

The source derives from these upstream revisions:

| Project | Revision |
|---|---|
| agg23/openfpga-NES | [`be5f1303a0df15d012155cb248b6174bb81e64b6`](https://github.com/agg23/openfpga-NES/tree/be5f1303a0df15d012155cb248b6174bb81e64b6) |
| MiSTer-devel/NES_MiSTer | [`49a0a66`](https://github.com/MiSTer-devel/NES_MiSTer/tree/49a0a66) |
| snckrz/openfpga-NES-Analogizer | [`5afb6390cfdcfdd9923c1e07f4311092e2d1a135`](https://github.com/snckrz/openfpga-NES-Analogizer/tree/5afb6390cfdcfdd9923c1e07f4311092e2d1a135) |

## License

The project includes the [GNU General Public License, version 3](LICENSE).
Individual source files retain their author credits and license notices.
