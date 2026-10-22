"""Release dates must identify packages without changing the upstream version."""
from datetime import date
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "stamp_version", Path(__file__).resolve().parents[1] / "tools/stamp_version.py")
version_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version_tool)


class VersionTests(unittest.TestCase):
    def test_date_stamp_preserves_base_and_synchronizes_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            core = root / "pkg/pocket/Cores/groucho.NES_experimental/core.json"
            core.parent.mkdir(parents=True)
            core.write_text(json.dumps({"core": {"metadata": {
                "shortname": "NES_experimental", "version": "1.0.1+20261021",
                "date_release": "2026-10-21"}, "framework": {"sleep_supported": True}}}))
            gateware = root / "gateware.json"
            gateware.write_text(json.dumps({"name": "NES_experimental", "version": "1.0.1"}))
            result = version_tool.stamp_version(root, date(2026, 10, 22))
            self.assertEqual(result, "1.0.1+20261022")
            metadata = json.loads(core.read_text())["core"]["metadata"]
            self.assertEqual(metadata["date_release"], "2026-10-22")
            self.assertEqual(metadata["version"], json.loads(gateware.read_text())["version"])
            self.assertTrue(json.loads(core.read_text())["core"]["framework"]["sleep_supported"])
            original = (core.read_bytes(), gateware.read_bytes())
            version_tool.stamp_version(root, date(2026, 10, 22))
            self.assertEqual(original, (core.read_bytes(), gateware.read_bytes()))

    def test_invalid_base_does_not_write_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            core = root / "pkg/pocket/Cores/groucho.NES_experimental/core.json"
            core.parent.mkdir(parents=True)
            core.write_text(json.dumps({"core": {"metadata": {"version": "invalid"}}}))
            gateware = root / "gateware.json"
            gateware.write_text("{}")
            original = (core.read_bytes(), gateware.read_bytes())
            with self.assertRaises(ValueError):
                version_tool.stamp_version(root, date(2026, 10, 22))
            self.assertEqual(original, (core.read_bytes(), gateware.read_bytes()))
