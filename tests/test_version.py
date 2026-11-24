"""The package version must be one plain version number in both definitions."""
import datetime
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VersionTests(unittest.TestCase):
    def test_definitions_agree(self):
        core, = (ROOT / "pkg/pocket/Cores").iterdir()
        metadata = json.loads((core / "core.json").read_text())["core"]["metadata"]
        gateware = json.loads((ROOT / "gateware.json").read_text())
        self.assertRegex(metadata["version"], re.compile(r"\A\d+\.\d+\.\d+\Z"))
        self.assertEqual(metadata["version"], gateware["version"])
        self.assertEqual(core.name, f"{metadata['author']}.{metadata['shortname']}")
        self.assertEqual(gateware["name"], metadata["shortname"])
        datetime.date.fromisoformat(metadata["date_release"])
