#!/bin/bash
# Build the exact production renderer; do not apply the newer upstream patch stack.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
source_dir=${1:?Usage: build-ghostty.sh SOURCE TARGET OUTPUT}
target=${2:?}
output=${3:?}
expected_zig=$(python3 -c 'import json; print(json.load(open("Paging/recipe.json"))["zig"])')
[[ $(zig version) == "$expected_zig" ]] || { echo "[!] Zig $expected_zig required" >&2; exit 1; }
./Script/apply-patches.sh "$source_dir"
case "$target" in
    aarch64-macos) sdk=macosx; clang_target=arm64-apple-macos13.0; cpu=apple_m1 ;;
    x86_64-macos) sdk=macosx; clang_target=x86_64-apple-macos13.0; cpu= ;;
    aarch64-ios) sdk=iphoneos; clang_target=arm64-apple-ios15.0; cpu=apple_a12 ;;
    aarch64-ios-simulator) sdk=iphonesimulator; clang_target=arm64-apple-ios15.0-simulator; cpu=apple_m1 ;;
    x86_64-ios-simulator) sdk=iphonesimulator; clang_target=x86_64-apple-ios15.0-simulator; cpu= ;;
    *) echo "[!] Unsupported paging target: $target" >&2; exit 1 ;;
esac
cache=${BUILD_CACHE_ROOT:-$root/build/cache}
mkdir -p "$cache" "$output/lib" "$output/include/libghostty"
cache=$(cd "$cache" && pwd)
output=$(cd "$output" && pwd)
case "$target" in
    *-ios*) export ZIG_LIB_DIR="$(./Script/prepare-zig-lib.sh "$cache" ios-std)" ;;
esac
args=(build -Demit-exe=false -Demit-macos-app=false -Demit-xcframework=false
    -Demit-docs=false -Dsentry=false -Doptimize=ReleaseSafe -Dapp-runtime=none
    "-Dtarget=$target"
    --cache-dir "$cache/$target" --prefix "$output" --summary failures)
if [[ -n "$cpu" ]]; then args+=("-Dcpu=$cpu"); fi
(cd "$source_dir"; ZIG_GLOBAL_CACHE_DIR="$cache/zig-global" zig "${args[@]}")
xcrun --sdk "$sdk" clang -target "$clang_target" -Os -fno-sanitize=undefined \
    -c "$root/Script/support/libcxx-verbose-abort-compat.c" -o "$cache/$target-compat.o"
xcrun libtool -static -no_warning_for_no_symbols -o "$output/lib/libghostty-compat.a" \
    "$output/lib/libghostty.a" "$cache/$target-compat.o"
mv "$output/lib/libghostty-compat.a" "$output/lib/libghostty.a"
cp "$source_dir/include/ghostty.h" "$output/include/libghostty/ghostty.h"
cat > "$output/include/libghostty/module.modulemap" <<'MODULE'
module libghostty {
    umbrella header "ghostty.h"
    export *
}
MODULE
