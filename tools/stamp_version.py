#!/usr/bin/env python3
"""Apply the upstream base version and UTC package build date to core metadata."""
import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def stamp_version(root, build_date):
    core_path = root / "pkg/pocket/Cores/groucho.NES_experimental/core.json"
    gateware_path = root / "gateware.json"
    core = json.loads(core_path.read_text())
    gateware = json.loads(gateware_path.read_text())
    metadata = core["core"]["metadata"]
    base = metadata["version"].split("+", 1)[0]
    if not re.fullmatch(r"\d+\.\d+\.\d+", base):
        raise ValueError("Core version must start with an upstream major.minor.patch version")
    version = f"{base}+{build_date:%Y%m%d}"
    metadata.update(version=version, date_release=build_date.isoformat())
    gateware["version"] = version
    core_path.write_text(json.dumps(core, indent=2) + "\n")
    gateware_path.write_text(json.dumps(gateware, indent=4) + "\n")
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", type=date.fromisoformat,
                        default=datetime.now(timezone.utc).date(),
                        help="Package build date (YYYY-MM-DD); default: current UTC date")
    args = parser.parse_args()
    print(stamp_version(ROOT, args.date))


if __name__ == "__main__":
    main()
