#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
results_root="$(dirname "$project_root")/build-results"
compiler_image=ghcr.io/drizzt/quartus@sha256:b5b0f0b7af271a0b9e9adc0cad59ff773d8690742a1426500fd71056d2c09787
for variant in discrete special expansion vrc7; do
    build_name="pocket-nes-build-${variant}-001"
    printf 'Building %s\n' "$variant"
    docker run --name "$build_name" --platform linux/amd64 --cpus 3 --memory 3g \
        --mount "type=bind,source=$project_root,target=/source,readonly" \
        --mount "type=volume,source=$build_name,target=/build" \
        "$compiler_image" bash /source/tools/build.sh "$variant"
    mkdir -p "$results_root/$variant"
    docker cp "$build_name:/build/results/." "$results_root/$variant/"
done
