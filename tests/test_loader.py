"""Execute the assembled Chip32 loader against synthetic slots; no game ROMs."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VM:
    def __init__(self, slots):
        self.memory = bytearray(8192)
        code = (ROOT / "pkg/pocket/Cores/groucho.NES_experimental/loader.bin").read_bytes()
        self.memory[:len(code)] = code
        self.reg = [0] * 16
        self.pc = 2
        self.zero = False
        self.slots = slots
        self.opened = None
        self.position = 0
        self.events = []
        self.output = []

    def word(self, size=2):
        value = int.from_bytes(self.memory[self.pc:self.pc + size], "little")
        self.pc += size
        return value

    def run(self):
        for _ in range(3000):
            word = self.word()
            op, x, y = word >> 8, word & 15, (word >> 4) & 15
            if word >= 0x6000:
                cond = word >> 12
                if cond == 6 or cond == 7 and not self.zero or cond == 8 and self.zero:
                    self.pc = (word & 4095) * 2
            elif op in (0x02, 0x04, 0x06):
                address = self.word()
                size = {2: 1, 4: 2, 6: 4}[op]
                self.reg[x] = int.from_bytes(self.memory[address:address + size], "little")
                self.zero = self.reg[x] == 0
            elif op in (0x08, 0x18, 0x09, 0x0D, 0x0E, 0x1E, 0x0F):
                value = self.word(4 if op & 0x10 else 2)
                if op in (8, 0x18): self.reg[x] = value
                elif op == 9: self.reg[x] &= value
                elif op == 13: self.reg[x] = (self.reg[x] - value) & 0xffffffff
                elif op in (14, 30):
                    self.zero = self.reg[x] == value
                    continue
                elif op == 15:
                    self.zero = self.reg[x] & value == 0
                    continue
                self.zero = self.reg[x] == 0
            elif op in (0x24, 0x25):
                self.reg[x] = ((self.reg[x] << (y + 1)) & 0xffffffff) if op == 0x24 else self.reg[x] >> (y + 1)
                self.zero = self.reg[x] == 0
            elif op in (0x28, 0x2A):
                self.reg[x] = self.reg[y] if op == 0x28 else self.reg[x] | self.reg[y]
                self.zero = self.reg[x] == 0
            elif op == 0x39:
                def string(address):
                    end = self.memory.index(0, address)
                    return self.memory[address:end]
                self.zero = string(self.reg[x]) == string(self.reg[y])
            elif op == 0x3E:
                self.reg[x], self.reg[y] = divmod(self.reg[x], self.reg[y])
                self.zero = self.reg[x] == 0
            elif op == 0x54:
                extension = self.slots[self.reg[x]][0].rsplit(".", 1)[-1].upper().encode() + b"\0"
                start = self.reg[y]
                self.memory[start:start + len(extension)] = extension
            elif op == 0x55:
                name=self.slots[self.reg[x]][0].encode()+b'\0'
                start=self.reg[y]
                self.memory[start:start+len(name)]=name
            elif op == 0x56:
                self.opened = self.slots.get(self.reg[x])
                self.position = 0
                self.zero = self.opened is not None
                if self.zero: self.reg[y] = len(self.opened[1])
            elif op == 0x57:
                self.opened = None
            elif op == 0x59:
                length = self.reg[y]
                self.zero = self.opened is not None and self.position + length <= len(self.opened[1])
                if self.zero:
                    start = self.reg[x]
                    self.memory[start:start + length] = self.opened[1][self.position:self.position + length]
                    self.position += length
            elif op in (0x53, 0x5D):
                slot = self.reg[x]
                self.zero = slot in self.slots
                if op == 0x53 and self.zero:
                    self.events.append(("load", slot))
                    self.reg[x] = len(self.slots[slot][1])
            elif op == 0x5B:
                self.events.append(("core", self.reg[x]))
            elif op == 0x5C:
                self.events.append(("host", self.reg[x]))
            elif op == 0x40:
                start=self.reg[x];end=self.memory.index(0,start)
                self.output.append(self.memory[start:end].decode())
            elif op == 0x41:
                digits={0:2,1:4,2:8}[y]
                self.output.append(f'{self.reg[x] & ((1 << (digits*4))-1):0{digits}X}')
            elif op == 0x46:
                return word & 1
            else:
                raise AssertionError(f"Unimplemented opcode {word:04x} at {self.pc - 2:04x}")
        raise AssertionError("Loader did not terminate")


def nes(mapper, nes2=True):
    header = bytearray(b"NES\x1a" + bytes(12))
    header[4] = 1
    header[6] = (mapper & 15) << 4
    header[7] = (mapper & 0xf0) | (8 if nes2 else 0)
    header[8] = mapper >> 8
    return bytes(header)


class LoaderTests(unittest.TestCase):
    def test_every_cartridge_mapper_and_extended_ids(self):
        manifest = json.loads((ROOT / "mapper_manifest.json").read_text())
        count = 0
        for variant in manifest["variants"]:
            if variant["name"] == "fds": continue
            for mapper in variant["mappers"]:
                with self.subTest(mapper=mapper):
                    vm = VM({0: ("test.nes", nes(mapper))})
                    self.assertEqual(vm.run(), 0)
                    self.assertEqual(vm.events, [("core", variant["id"]), ("load", 0), ("host", 0x4002)])
                    count += 1
        self.assertEqual(count, 144)

    def test_dirty_ines_matches_hardware(self):
        header = bytearray(nes(133, nes2=False))
        header[9] = 2
        vm = VM({0: ("dirty.nes", header)})
        self.assertEqual(vm.run(), 0)
        self.assertEqual(vm.events[0], ("core", 3))  # mapper 5, not 133

    def test_fc_extension_routes_all_cartridge_mappers_and_loads_saves(self):
        manifest = json.loads((ROOT / "mapper_manifest.json").read_text())
        for variant in manifest["variants"]:
            if variant["name"] == "fds": continue
            for mapper in variant["mappers"]:
                for extension in ("fc", "FC", "Fc"):
                    with self.subTest(mapper=mapper, extension=extension):
                        vm = VM({0: ("test." + extension, nes(mapper)),
                                 10: ("test.sav", bytes(8192))})
                        self.assertEqual(vm.run(), 0)
                        self.assertEqual(vm.events, [("core", variant["id"]), ("load", 0),
                                                     ("load", 10), ("host", 0x4002)])

        # An .fc suffix uses exactly the same iNES 1.0 header interpretation.
        vm = VM({0: ("test.fc", nes(69, nes2=False))})
        self.assertEqual(vm.run(), 0)
        self.assertEqual(vm.events[0], ("core", 3))

    def test_fds_side_counts_and_load_order(self):
        for sides in range(1, 5):
            for header in (False, True):
                disk = bytes(sides * 65500)
                if header: disk = b"FDS\x1a" + bytes([sides]) + bytes(11) + disk
                save=bytearray(262144)
                save[16:31]=b'\x01*NINTENDO-HVC*'
                vm = VM({0: ("disk.fds", disk), 1: ("fds.bios", bytes(8192)),
                         10: ("disk.sav", save), 11: ("custom.pal", bytes(192))})
                self.assertEqual(vm.run(), 0)
                self.assertEqual(vm.events, [("core", 5), ("load", 1), ("load", 0),
                                             ("load", 11), ("load", 10), ("host", 0x4002)])

    def test_rejects_damaged_fds_save_before_copying_it(self):
        for save in [bytes(262144), bytes(131000), b'\xa4'*262144]:
            vm=VM({0:('disk.fds',bytes(65500)),1:('fds.bios',bytes(8192)),10:('disk.sav',save)})
            self.assertEqual(vm.run(),1)
            self.assertNotIn(('load',10),vm.events)
            self.assertNotIn(('host',0x4002),vm.events)
            self.assertIn('disk.sav',''.join(vm.output))
            self.assertIn(f'{len(save):08X}',''.join(vm.output))

    def test_cartridge_saves_do_not_require_fds_header(self):
        vm=VM({0:('cart.nes',nes(1)),10:('cart.sav',bytes(8192))})
        self.assertEqual(vm.run(),0)
        self.assertIn(('load',10),vm.events)

    def test_rejects_invalid_inputs_before_configuring_fpga(self):
        trainer = bytearray(nes(0)); trainer[6] |= 4
        cases = [({0: ("x.nsf", bytes(128))}), {0: ("x.nes", bytes(16))},
                 {0: ("x.nes", trainer)}, {0: ("x.nes", nes(1023))},
                 {0: ("x.fc", bytes(16))}, {0: ("x.FC", trainer)},
                 {0: ("x.fc", nes(1023))}, {0: ("x.bin", nes(0))},
                 {0: ("x.fds", bytes(65501)), 1: ("fds.bios", bytes(8192))},
                 {0: ("x.fds", bytes(65500))},
                 {0: ("x.fds", bytes(65500)), 1: ("fds.bios", bytes(8191))}]
        for slots in cases:
            vm = VM(slots)
            self.assertEqual(vm.run(), 1)
            self.assertFalse(vm.events)


if __name__ == "__main__":
    unittest.main()
