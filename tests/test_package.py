"""Archive exclusions must preserve the core's required binary assets."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "core_package", Path(__file__).resolve().parents[1] / "tools/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def test_every_menu_entry_is_visible_on_pocket(self):
        core, = (Path(__file__).resolve().parents[1] / "pkg/pocket/Cores").iterdir()
        menu = json.loads((core / "interact.json").read_text())["interact"]["variables"]
        package.validate_menu(menu)
        self.assertLessEqual({"Eject / Change Disk", "Disk Swap", "Fast Disk Access"},
                             {v["name"] for v in menu})

    def test_rejects_menu_entries_that_pocket_would_drop(self):
        entry = {"name": "Setting", "type": "check"}
        package.validate_menu([entry] * 16)
        for menu in ([entry] * 17, [{"name": "x" * 24}],
                     [{"name": "List", "options": [{"name": "x"}] * 17}]):
            with self.subTest(menu=len(menu)), self.assertRaises(ValueError):
                package.validate_menu(menu)

    def test_local_build_notes_and_python_cache_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "source"
            for name in ("release-notes/private.json", "docs/PLL Reconfig.md", "tests/__pycache__/test.pyc", "README.md", "tests/test_loader.py"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic fixture")
            output = Path(temporary) / "source.zip"
            package.archive_tree(root, output, "pocket-nes/")
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {"pocket-nes/README.md", "pocket-nes/tests/test_loader.py"})

    def test_installer_preserves_common_directory_without_git_placeholder(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "stage"
            common = root / "Assets/nes/common"
            common.mkdir(parents=True)
            (common / ".gitkeep").touch()
            output = Path(temporary) / "installer.zip"
            package.archive_tree(root, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.namelist(), ["Assets/nes/common/"])

    def test_rom_bios_and_save_exclusion_preserves_core_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "source"
            root.mkdir()
            excluded = ["test" + suffix for suffix in package.PRIVATE_ASSET_SUFFIXES]
            excluded += [name.upper() for name in excluded]
            included = ["loader.bin", "icon.bin", "font.chr", "table.mif", "fds.rev", "test_loader.py"]
            for name in excluded + included:
                (root / name).write_bytes(b"synthetic fixture")
            output = Path(temporary) / "source.zip"
            package.archive_tree(root, output, "pocket-nes/")
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {"pocket-nes/" + n for n in included})
