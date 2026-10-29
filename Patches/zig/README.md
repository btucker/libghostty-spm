# Zig patches

Patches to the Zig *standard library*, for targets the pinned Zig only half
knows. They are applied to a copy of the toolchain's `lib/` staged under the
build cache by `Script/prepare-zig-lib.sh`, never to the installation itself;
`Script/build-ghostty.sh` exports that copy as `ZIG_LIB_DIR` for iOS targets.
macOS builds use the installed standard library.

Files are named `<zig version>-<patch name>.patch` and applied with
`patch -p1` from the lib directory. Paths start at `std/`.
The build receipt hashes patches for the exact compiler version and the
staging script. Missing required patches fail the build.

## Patches

`0.17.0-ios-std.patch` marks process replacement unsupported on iOS, tvOS,
visionOS, and watchOS, matching Zig's process-spawn policy. Without this fix,
`Io.Threaded.processReplace` instantiates Darwin spawn code that accesses a
nonexistent `NullFile.fd` on iOS.

The historical `0.15.2-visionos-std.patch` added missing visionOS branches.
Zig 0.16.0 includes those branches, so that patch was removed.
