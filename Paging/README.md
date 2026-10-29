# Production paging package

This fork owns the production renderer used by Graftty on macOS and iOS.
`recipe.json` preserves engine `8af6897c0afc63037a8a3efee4162a380e3a4572`,
Zig 0.16.0, and the eleven native patches previously assembled in Graftty.
`screen-text-history.patch` also retains the wrapper fork's existing absolute
history selection fix on this engine. The full wrapper test suite exposed its
absence when reading rows beyond the live grid; no engine upgrade is needed.
The three Swift wrapper patches are applied directly to `Sources/` and `Tests/`,
on wrapper baseline `da4d8ddc94ba66f89efa5208961a1116357117c3`.
The snapshot ABI remains `ghostty-8af6897c-paging-1`, compatible with Graftty's
existing zmx producer. This change does not upgrade the engine or zmx.

The production package contains universal macOS, arm64 iOS, and universal iOS
Simulator slices. Catalyst and visionOS require a separate engine integration;
this release does not advertise those platforms. The former `Patches/ghostty`
stack targets the newer engine and is not applied by the production build.
Weekly automatic engine upgrades have been removed so source changes require
an explicit patch and snapshot compatibility review.

Run `./build.sh` with Xcode, the Metal toolchain, and Zig 0.16.0 on PATH.
Use `--source PATH` for an isolated clean checkout of `Ghostty.ref`.
`BUILD_CACHE_ROOT` can place native caches on another volume.
A changed patch recipe requires a fresh source checkout. Do not reuse a source
checkout concurrently. The build writes `BinaryTarget/GhosttyKit.xcframework`,
`build/GhosttyKit.xcframework.zip`, and `PAGING-BUILD.json`.
The receipt hashes the exact recipe, patches, Swift sources, and every artifact
file. Each native slice records its actual compiler checksum, Xcode and SDK builds,
archive hash, and header hash; the assembly toolchain is recorded separately.
ZIP entries use fixed timestamps, modes, and ordering for reproducible packaging. Run `python3 Paging/provenance.py verify` to validate a local package.
After rebuilding Swift wrappers against an unchanged binary, explicitly refresh
its receipt with `python3 Paging/provenance.py refresh-wrapper --source "$(git rev-parse HEAD)"`.
Do not refresh a receipt for native changes without rebuilding the binary.
For a Graftty local override, copy `Package.local.swift` to `Package.swift` after
building. Graftty rejects overrides that still select a remote binary target.

Publication uses the existing two-stage release route:

1. Dispatch `build.yml` on the reviewed branch. It builds all five slices and
   publishes the immutable `upstream.<Ghostty.ref prefix>-<Ghostty.build>` storage
   release, with the XCFramework, receipt, and SHA256SUMS.
2. Dispatch `release.yml` on the same branch. It downloads and verifies the
   storage receipt, generates the remote manifest with the ZIP checksum, builds
   the supported destinations, and runs the Swift tests. It commits the manifest
   and receipt, then publishes the package version. Never push a semver tag by hand.

Bump `Ghostty.build` whenever native patch inputs change for the same engine.
Never replace an existing storage asset. Graftty pins the resulting package
commit and uses it for development, CI, and release builds.

Run `python3 Paging/test-provenance.py` for receipt rejection tests.
Run `Paging/production-test-surfaces.sh SOURCE ZIG SIMULATOR_UDID` for native
AppKit and UIKit checkpoint, history, selection, grid-order, and teardown probes.
Set `LIBGHOSTTY_TEST_XCFRAMEWORK` to the extracted published XCFramework to test
its exact archives instead of rebuilding the renderer.
`Paging/test-core.sh` tests snapshot allocation and incremental decode.
`Paging/test-link-clicks.sh SOURCE ZIG MACOS_ARCHIVE` tests restored file links
against the packaged macOS archive.
