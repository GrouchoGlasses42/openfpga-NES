#!/usr/bin/env python3
"""Package only a complete six-image build with reviewed compiler timing."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import tempfile
import zipfile


PRIVATE_ASSET_SUFFIXES = frozenset({
    ".nes", ".fds", ".fc", ".unf", ".unif", ".qd", ".nsf", ".nsfe",
    ".rom", ".bios", ".sav", ".srm",
    ".zip", ".7z", ".rar",
})


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def validate_core_definition(folder):
    """Check firmware-facing limits, beyond whether the JSON parses."""
    core = json.loads((folder / "core.json").read_text())["core"]
    metadata = core["metadata"]
    errors = []
    for field, limit in {"shortname": 31, "author": 31, "description": 63,
                         "url": 63, "version": 31, "date_release": 10}.items():
        value = metadata.get(field)
        if not isinstance(value, str) or not 1 <= len(value) <= limit:
            errors.append(f"metadata.{field} must contain 1 to {limit} characters")
    expected = f"{metadata.get('author')}.{metadata.get('shortname')}"
    if folder.name != expected:
        errors.append(f"core folder {folder.name!r} must match author.shortname {expected!r}")
    images = core["cores"]
    if not 1 <= len(images) <= 8:
        errors.append("core must list 1 to 8 bitstreams")
    files = [image["filename"] for image in images]
    vm = core["framework"].get("chip32_vm")
    if vm is not None:
        files.append(vm)
    for name in files:
        if not isinstance(name, str) or not 1 <= len(name) <= 15 or Path(name).name != name:
            errors.append(f"invalid core filename: {name!r}")
        elif not (folder / name).is_file():
            errors.append(f"missing core file: {name}")
    if errors:
        raise ValueError("; ".join(errors))
    return metadata


def validate(folder, name):
    log = (folder / "build.log").read_text()
    if "Quartus Prime Full Compilation was successful. 0 errors" not in log:
        raise ValueError(f"{name}: compilation failed")
    if "Critical Warning (127003)" in log or "Warning (12019)" in log:
        raise ValueError(f"{name}: missing source or memory initialization file")
    summary = (folder / "nes_pocket.fit.summary").read_text()
    if "Fitter Status : Successful" not in summary:
        raise ValueError(f"{name}: fitting failed")
    timing = (folder / "nes_pocket.sta.summary").read_text()
    entries = re.findall(r"Type\s+: (.+)\nSlack : ([-.0-9]+)\nTNS\s+: ([-.0-9]+)", timing)
    if not entries or any(float(slack) < 0 or float(tns) < 0 for _, slack, tns in entries):
        raise ValueError(f"{name}: timing failed")
    full = (folder / "nes_pocket.sta.rpt").read_text()
    if not re.search(r"; Unconstrained Clocks\s*;\s*0\s*;\s*0\s*;", full):
        raise ValueError(f"{name}: unconstrained clocks")
    image = folder / (name + ".rbf")
    if image.stat().st_size < 1_000_000:
        raise ValueError(f"{name}: unexpectedly small FPGA image")
    alm = re.search(r"Logic utilization \(in ALMs\) : ([\d,]+) / ([\d,]+)", summary)
    return {"rbf_sha256": digest(image), "logic_alms": int(alm[1].replace(",", "")),
            "capacity_alms": int(alm[2].replace(",", "")),
            "minimum_slack_ns": {kind: min(float(s) for t, s, _ in entries if " " + kind + " " in t)
                                 for kind in ["Setup", "Hold", "Recovery", "Removal"]},
            "critical_warnings": re.findall(r"^Critical Warning.*$", log, re.M),
            "unconstrained_external_io": "Design is not fully constrained" in log}


def archive_tree(root, output, prefix=""):
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        if not prefix and (root / "Assets/nes/common").is_dir():
            archive.writestr("Assets/nes/common/", b"")
        for path in sorted(root.rglob("*")):
            relative = path.relative_to(root)
            if (path.is_file() and not {".git", "__pycache__", "release-notes"}.intersection(relative.parts)
                    and path.suffix.lower() not in PRIVATE_ASSET_SUFFIXES
                    and (prefix or path.name != ".gitkeep")):
                archive.write(path, prefix + path.relative_to(root).as_posix())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP integrity check failed")


def validate_source(source, results):
    """Require exact FPGA inputs, while permitting separate loader/metadata updates."""
    manifest_path = results / "source-manifest.json"
    compiled = json.loads(manifest_path.read_text())
    current = {p.relative_to(source).as_posix(): digest(p)
               for p in source.rglob("*") if p.is_file()
               and ".git" not in p.parts and "__pycache__" not in p.parts}
    prefixes = ("rtl/", "target/", "platform/", "projects/", "generated/")
    scripts = {"tools/build.sh", "tools/configure_variant.py", "mapper_manifest.json"}
    compiler_files = {k for k in set(compiled) | set(current)
                      if k.startswith(prefixes) or k in scripts}
    if not compiler_files or not scripts <= compiler_files:
        raise ValueError("Missing compiler input manifest")
    differences = sorted(k for k in compiler_files if compiled.get(k) != current.get(k))
    if differences:
        raise ValueError("FPGA sources differ from compiled inputs: " + ", ".join(differences))
    return {"compiled_source_manifest_sha256": digest(manifest_path),
            "compilation_results": str(results), "checked_fpga_input_files": len(compiler_files),
            "fpga_input_differences": differences,
            "other_changed_files": sorted(k for k in set(compiled) | set(current)
                                          if compiled.get(k) != current.get(k)),
            "note": "FPGA inputs match this build's recorded source; per-image execution reports record compilation or reuse provenance."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    equivalence = validate_source(args.source, args.results)
    mapper_manifest = json.loads((args.source / "mapper_manifest.json").read_text())
    mapping = [n for v in mapper_manifest["variants"] for n in v["mappers"]]
    if len(mapping) != len(set(mapping)) or len(mapping) != mapper_manifest["mapper_count"]:
        raise ValueError("Mapper inventory is inconsistent")
    reports = {v["name"]: validate(args.results / v["name"], v["name"])
               for v in mapper_manifest["variants"]}
    args.output.mkdir(parents=True, exist_ok=True)
    table = bytes(int(f"{n:08b}"[::-1], 2) for n in range(256))
    with tempfile.TemporaryDirectory(prefix="pocket-nes-release-") as temporary:
        stage = Path(temporary)
        shutil.copytree(args.source / "pkg/pocket", stage, dirs_exist_ok=True)
        core_folders = list((stage / "Cores").iterdir())
        if len(core_folders) != 1 or not core_folders[0].is_dir():
            raise ValueError("Expected exactly one core definition")
        core = core_folders[0]
        core_id = core.name
        for variant in mapper_manifest["variants"]:
            raw = (args.results / variant["name"] / (variant["name"] + ".rbf")).read_bytes()
            target = core / variant["filename"]
            target.write_bytes(raw.translate(table))
            if target.read_bytes().translate(table) != raw:
                raise ValueError("Bitstream conversion did not round-trip")
        checked_metadata = validate_core_definition(core)
        version = checked_metadata["version"]
        date = checked_metadata["date_release"]
        menu = json.loads((core / "interact.json").read_text())["interact"]["variables"]
        ids = [v["id"] for v in menu]
        addresses = [int(v["address"], 0) for v in menu if "address" in v]
        if len(ids) != len(set(ids)) or len(addresses) != len(set(addresses)):
            raise ValueError("Duplicate menu ID or bridge address")
        documentation = stage / "Documentation" / core_id
        documentation.mkdir(parents=True)
        for name in ["README.md", "LICENSE"]:
            shutil.copy2(args.source / name, documentation / name)
        hashes = {}
        for path in stage.rglob("*"):
            if (path.is_file() and path.name != ".gitkeep"
                    and path.suffix.lower() not in PRIVATE_ASSET_SUFFIXES):
                if path.suffix == ".json": json.loads(path.read_text())
                hashes[path.relative_to(stage).as_posix()] = digest(path)
        label = version if version.endswith("+" + date.replace("-", "")) else f"{version}_{date}"
        package = args.output / f"{core_id}_{label}.zip"
        archive_tree(stage, package)
    source_package = args.output / f"pocket-nes-source_{label}.zip"
    archive_tree(args.source, source_package, "pocket-nes/")
    manifest = {"package": package.name, "package_sha256": digest(package),
                "source_package": source_package.name, "source_package_sha256": digest(source_package),
                "quartus_image": "ghcr.io/drizzt/quartus@sha256:b5b0f0b7af271a0b9e9adc0cad59ff773d8690742a1426500fd71056d2c09787",
                "mapper_count": len(mapping), "variants": reports, "files_sha256": hashes,
                "hardware_tested": False, "source_equivalence": equivalence}
    (args.output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (args.output / "SHA256SUMS.txt").write_text(f"{digest(package)}  {package.name}\n{digest(source_package)}  {source_package.name}\n")
    print(package)
    print(source_package)


if __name__ == "__main__":
    main()
