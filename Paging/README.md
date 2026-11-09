# Production paging package

This fork owns the production renderer used by Graftty on macOS and iOS.
`recipe.json` pins engine `53e55147bbbb0157672dac0228aa7744e881f1fa`, Zig
0.17.0, and thirteen native patches applied in order. The engine is the
Ghostty commit pinned by zmx v1.0.1, so Graftty's zmx daemons encode history
pages with the same page layout this renderer decodes. Change both together.
`screen-text-history.patch` retains the wrapper fork's absolute history
selection fix. `cursor-timer.patch` carries upstream libghostty-spm's fix that
stops the cursor timer from redrawing idle and unfocused surfaces.
The snapshot ABI remains `ghostty-8af6897c-paging-1` for the existing zmx
producer. The snapshot golden fixtures are unchanged from Ghostty 1.4.0 to
`53e55147`, and Graftty's paged suites pass with the shipped zmx. A zmx built on
this engine must still prove old decoders skip any new optional records.

Zig 0.17.0's standard library does not compile for iOS. `build-ghostty.sh`
builds iOS targets against a copy of the std staged by
`Script/prepare-zig-lib.sh` with `Patches/zig/0.17.0-ios-visionos-std.patch`.
It also runs `Paging/patch-zig-packages.py`, which fixes aro's Apple blocks
check in the fetched `zig-pkg/` tree so iOS headers translate. Both are native
inputs recorded by the provenance receipt.

The production package contains universal macOS, arm64 iOS, and universal iOS
Simulator slices. Catalyst and visionOS require a separate engine integration;
this release does not advertise those platforms. The former `Patches/ghostty`
stack targets the newer engine and is not applied by the production build.
Weekly automatic engine upgrades have been removed so source changes require
an explicit patch and snapshot compatibility review.

Run `./build.sh` with Xcode, the Metal toolchain, and Zig 0.17.0 on PATH.
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
   release, with the XCFramework, receipt, and SHA256SUMS. For a probe-only retry,
   `native_run_id` may reuse all five successful native jobs from a completed run.
   The workflow verifies that every native source input is unchanged before reuse.
2. Dispatch `release.yml` on the same branch. It downloads and verifies the
   storage receipt, generates the remote manifest with the ZIP checksum, builds
   the supported destinations, and runs the Swift tests. It commits the manifest
   and receipt, then publishes the package version. Never push a semver tag by hand.

When publishing a branch that changes `.github/workflows/` relative to `main`,
GitHub requires workflow-write authentication that `GITHUB_TOKEN` cannot have.
Dispatch each workflow with `publish=false`, then run
`python3 Script/finalize-release.py RUN_ID` with an authorized local `gh` login.
The helper accepts only a successful matching workflow, downloads its tested
handoff, verifies checksums and commit bindings, and publishes the exact result.
It refuses to replace an existing release. This uses the same assembly and test
route without storing the local credential in CI. Do not create tags manually.

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
