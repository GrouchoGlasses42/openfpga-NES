#!/bin/bash
set -euo pipefail
variant=${1:?Specify a variant}
mkdir -p /build/source /build/results
cp -a /source/. /build/source/
cd /build/source
cp generated/"$variant"/cart.sv rtl/upstream/cart.sv
cp generated/"$variant"/mapper_config.vh rtl/upstream/mapper_config.vh
cp generated/"$variant"/nes_pocket.qsf projects/nes_pocket.qsf
find rtl target platform projects -type f ! -path 'projects/db/*' ! -path 'projects/incremental_db/*' ! -path 'projects/output_files/*' -exec sha256sum '{}' \; > /build/results/source-sha256.txt
printf 'Variant: %s\nStarted: %s\n' "$variant" "$(date -u --iso-8601=seconds)" > /build/results/status.txt
# A standalone quartus_map invocation does not run the project's PRE_FLOW hook.
# Generate its required build-ID RAM before the synthesis preflight as well.
(cd projects && quartus_sh -t ../platform/pocket/build_id_gen.tcl) > /build/results/build-id.log 2>&1
set +e
(cd projects && quartus_map --read_settings_files=on --write_settings_files=off nes_pocket -c nes_pocket) > /build/results/map-preflight.log 2>&1
result=$?
if [ "$result" -eq 0 ] && grep -Eq 'Critical Warning \(127003\)|Warning \(12019\)' /build/results/map-preflight.log; then
    result=1
fi
if [ "$result" -eq 0 ]; then
    quartus_sh --flow compile projects/nes_pocket.qpf > /build/results/build.log 2>&1
    result=$?
else
    cp /build/results/map-preflight.log /build/results/build.log
fi
set -e
find projects/output_files -maxdepth 1 -type f \( -name '*.rpt' -o -name '*.summary' -o -name '*.smsg' \) -exec cp '{}' /build/results/ \;
if [ "$result" -eq 0 ]; then
    cp projects/output_files/nes_pocket.rbf /build/results/"$variant".rbf
fi
printf 'Exit: %s\nFinished: %s\n' "$result" "$(date -u --iso-8601=seconds)" >> /build/results/status.txt
tail -40 /build/results/build.log
exit "$result"
