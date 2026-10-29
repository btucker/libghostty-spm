#!/bin/bash
# Exercise the exact packaged archives on AppKit and UIKit before publication.
set -euo pipefail
cd "$(dirname "$0")/.."
source_dir=${1:?Usage: Paging/test-published.sh PATCHED_SOURCE ZIG}
zig_bin=${2:?}
export LIBGHOSTTY_TEST_XCFRAMEWORK="$PWD/BinaryTarget/GhosttyKit.xcframework"
python3 Paging/provenance.py verify
runtime=$(xcrun simctl list runtimes --json | python3 -c 'import json,sys; print(next(r["identifier"] for r in reversed(json.load(sys.stdin)["runtimes"]) if r.get("isAvailable") and ".iOS-" in r["identifier"]))')
device=$(xcrun simctl list devicetypes --json | python3 -c 'import json,sys; print(next(d["identifier"] for d in json.load(sys.stdin)["devicetypes"] if "iPhone" in d["name"]))')
simulator=$(xcrun simctl create LibghosttyPagingPublication "$device" "$runtime")
cleanup() {
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator"
}
trap cleanup EXIT
Paging/production-test-surfaces.sh "$source_dir" "$zig_bin" "$simulator"
