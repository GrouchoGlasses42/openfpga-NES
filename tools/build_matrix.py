#!/usr/bin/env python3
"""Compile an immutable source snapshot with at most two Quartus jobs."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "ghcr.io/drizzt/quartus@sha256:b5b0f0b7af271a0b9e9adc0cad59ff773d8690742a1426500fd71056d2c09787"
RUN_ID = "009"
SNAPSHOT = ROOT.parent / ("build-inputs/pocket-nes-verified-" + RUN_ID)
RESULTS = ROOT.parent / ("build-results/verified-" + RUN_ID)


def run_variant(variant):
    name = variant["name"]
    container = f"pocket-nes-verified-{name}-{RUN_ID}"
    # Retain the previous job's compiler database for Quartus smart recompilation.
    volume = f"pocket-nes-verified-{name}-001"
    folder = RESULTS / name
    folder.mkdir(parents=True, exist_ok=True)
    command = ["docker", "run", "--name", container, "--platform", "linux/amd64",
               "--cpus", "3", "--memory", "3g",
               "--mount", f"type=bind,source={SNAPSHOT},target=/source,readonly",
               "--mount", f"type=volume,source={volume},target=/build",
               IMAGE, "bash", "/source/tools/build.sh", name]
    start = time.monotonic()
    print(f"START {name}", flush=True)
    with (folder / "container.log").open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    subprocess.run(["docker", "cp", f"{container}:/build/results/.", str(folder)], check=True)
    report = {"variant": name, "container": container, "exit_code": result.returncode,
              "seconds": round(time.monotonic() - start, 1)}
    (folder / "execution.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"FINISH {name}: exit={result.returncode}, elapsed={report['seconds']}s", flush=True)
    return report


def main():
    if SNAPSHOT.exists():
        raise SystemExit(f"Snapshot already exists: {SNAPSHOT}")
    shutil.copytree(ROOT, SNAPSHOT, ignore=shutil.ignore_patterns(".git", "__pycache__", "db", "incremental_db", "output_files"))
    manifest = json.loads((SNAPSHOT / "mapper_manifest.json").read_text())
    RESULTS.mkdir(parents=True, exist_ok=True)
    hashes = {p.relative_to(SNAPSHOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(SNAPSHOT.rglob("*")) if p.is_file()}
    (RESULTS / "source-manifest.json").write_text(json.dumps(hashes, indent=2) + "\n")
    reports = []
    pending = []
    previous = ROOT.parent / "build-results/verified-008"
    old_manifest = previous / "source-manifest.json"
    identical = False
    if old_manifest.exists():
        old = json.loads(old_manifest.read_text())
        prefixes = ("rtl/", "target/", "platform/", "projects/", "generated/", "chip32/", "pkg/pocket/")
        compiler_files = {k for k in set(old) | set(hashes) if k.startswith(prefixes)}
        differences = [k for k in compiler_files if old.get(k) != hashes.get(k)]
        identical = not differences
        (RESULTS / "source-equivalence.json").write_text(json.dumps({
            "previous": str(previous), "compiler_input_differences": differences,
            "note": "Only complete validated images with identical compiler inputs can be reused; build-script changes are not RTL changes."
        }, indent=2) + "\n")
    spec = importlib.util.spec_from_file_location("nes_package", SNAPSHOT / "tools/package.py")
    package = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(package)
    for variant in manifest["variants"]:
        name = variant["name"]
        if identical:
            try:
                package.validate(previous / name, name)
            except (ValueError, OSError):
                pass
            else:
                shutil.copytree(previous / name, RESULTS / name)
                report = json.loads((RESULTS / name / "execution.json").read_text())
                report["reused_from"] = str(previous / name)
                reports.append(report)
                print(f"REUSE {name}: compiler inputs identical and all checks pass", flush=True)
                continue
        pending.append(variant)
    pending.sort(key=lambda v: ["fds", "standard", "discrete", "special", "expansion", "vrc7"].index(v["name"]))
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(run_variant, variant) for variant in pending]
        for future in as_completed(futures):
            reports.append(future.result())
            (RESULTS / "execution.json").write_text(json.dumps(reports, indent=2) + "\n")
    if any(r["exit_code"] for r in reports):
        raise SystemExit(f"One or more variants failed; inspect {RESULTS}")


if __name__ == "__main__":
    main()
