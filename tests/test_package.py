"""Archive exclusions must preserve the core's required binary assets."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "core_package", Path(__file__).resolve().parents[1] / "tools/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
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
