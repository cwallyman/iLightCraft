# iLightCraft Xcode Cloud

Prepared 2026-10-25. Local script validation does not establish a successful cloud build.

## Build inputs

The native checkout is the repository root, not its parent LightCraftiPad directory.
Use `https://github.com/cwallyman/iLightCraft`, branch `ipad-lightcraft`, project
`iLightCraft.xcodeproj`, scheme `iLightCraft`, team `D58RZM4K8N`, and bundle ID
`com.cwallyman.iLightCraft`. Keep the current product version `0.11.0`.

`ci_scripts/ci_post_clone.sh` installs isolated Rust 1.95.0 and the three Apple
targets, creates a Python 3.12 environment for the pinned model conversion tools,
fetches the existing SHA-256-verified model sources and builds the Rust XCFramework.
Cargo uses the existing lockfile. This does not update the vendored engine.
The pre-build script checks that generated inputs exist and that no local identity
override was included. Neither script requires signing credentials or personal photos.

These scripts must be executable and committed alongside the native app source.
The current local rename and feature work must reach GitHub before a remote build can
use it; the previously pushed project still uses the old native project name.
Do not commit Frameworks, DerivedData, model packages, signing keys, development
identity overrides, device backups or `.xcode-cloud` environments.

## First-time Apple/GitHub connection

In Xcode, choose Product > Xcode Cloud > Create Workflow. Select iLightCraft.
Follow Apple's account authorization prompts; grant repository access only to
`cwallyman/iLightCraft`. Accept any Apple service terms yourself after reviewing them.
This is account setup, not a file that a shell script can enable.

Create an **iLightCraft iOS** workflow:

- Branch Changes: `ipad-lightcraft`; enable manual builds.
- Select Xcode 27.0 (the locally verified toolchain) and a compatible macOS version.
- Archive: scheme `iLightCraft`, Release, iOS (iPhone and iPad).
- Start build numbering above every uploaded build for the version; verify the current
  App Store Connect build list before setting it. The local source build number is 1;
  the previous upload allowed Xcode to manage its final number.
- Begin with no external TestFlight distribution or automatic public release.
  Add an internal TestFlight group after the first successful archive is processed.
- No custom secret environment variables are needed for these scripts; Apple manages signing.

Add a Release archive for Mac Catalyst, either as a second action or in a separate
**iLightCraft Mac** workflow with the same branch and toolchain. The engine currently supports Apple Silicon;
Intel Mac support is not established. Verify the archive's architecture settings.

Run the first builds manually, inspect post-clone and archive logs, and confirm each
build finishes processing in App Store Connect before enabling distribution post-actions.
The initial builds must fetch Rust crates and large Python wheels and compile three
engine targets, so their duration is not comparable to a warm local archive.

## Evidence and current limitations

Local iOS and Mac Catalyst 0.11.0 archives and uploads succeeded before this setup.
Logs: `LocalVerification/StoreUpload-20261025-v011/`. This is separate from Xcode Cloud
verification and does not establish physical feature acceptance or App Review approval.

Local checks for this setup: Bash syntax and the branding audit passed; an isolated
preflight check accepted complete generated inputs and rejected missing inputs/local
identity overrides; the locked Rust XCFramework rebuild passed for all three Apple
targets. Python 3.12 wheels were confirmed on PyPI for every pinned direct model-tool
dependency. The post-clone installer and model conversion have not run on an Apple
cloud worker. Xcode's first-workflow assistant now shows **Setup Complete** with
`ipad-lightcraft` selected. The Apple/GitHub connection and initial workflow are
configured; a successful cloud build is not yet verified. Publish the prepared
source before starting the first build. The workflow may start automatically on push.
The user confirmed selecting both iOS and Mac platforms in the initial setup;
verify both archive actions and their outputs in the first cloud build.

The initial cloud runs reached the model conversion setup but stopped when the
skin ONNX download failed its size/SHA-256 check. The pinned revision's Git LFS
metadata and a local download both confirm the existing size and digest. The
downloader now requests raw file bytes, assembles bounded partial reads, retries
rejected/interrupted downloads up to three times, and reports the received length
and digest on failure. The source pins remain unchanged; invalid bytes are never
accepted. Cloud verification of this download fix is pending.

The required parent-reference `cargo xtask ci` gate completed successfully before
publishing this snapshot (fmt, Clippy, HEIF, workspace tests, parity, layers, assets
and WASM). It reported 165 dependency/data skips: 137 corpus, 20 fonts and 8 models.
The report is in the parent checkout's `target/ci/summary.md`; these reference checks
are separate from native device acceptance and the first Xcode Cloud build.

References: [first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow),
[GitHub connection](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github),
[custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).
