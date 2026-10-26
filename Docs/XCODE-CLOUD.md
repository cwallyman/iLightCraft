# iLightCraft Xcode Cloud

Last updated: 2026-10-25.

## Verified workflow

The **iLightCraft** workflow builds both iOS/iPadOS and Mac Catalyst on branch
`ipad-lightcraft`, with branch-change and manual triggers. It uses project
`iLightCraft.xcodeproj`, scheme `iLightCraft`, Xcode 27.1 and macOS 27.0.1.
The product version is **0.11.0**, bundle ID `com.cwallyman.iLightCraft`, signing
team `D58RZM4K8N`. The native checkout is the repository root.

Both Cloud actions completed successfully at
[`303faf0`](https://github.com/cwallyman/iLightCraft/commit/303faf06baa18e79f35c4e8bb4d2042f30eb7b0d).
The iOS action reports no warnings; the Mac action reports one missing Metal
toolchain Swift search path on the Apple worker. This warning did not block the build.
The unused capture, redundant error cast and unnecessary isolation annotation in
Swift source have been removed.

For the Mac action, select platform **macOS** and **Build For: Any Mac (Mac Catalyst)**.
The framework supplies Apple Silicon Mac Catalyst, not a native macOS slice or Intel
support. Selecting the default native Mac destination causes linking to fail.

The current actions are **Build**, not Archive. Automatic Archive/TestFlight delivery
and distribution post-actions remain to be configured. No public release or App Review
approval is established by these builds.

## Generated build inputs

`ci_scripts/ci_post_clone.sh` installs isolated Rust 1.95.0 with device, simulator and
Mac Catalyst targets; prepares Python 3.12 and pinned model tools; runs nine Python
regression tests; fetches SHA-256-verified model sources; audits branding; and builds
the locked Rust XCFramework. The vendored engine is unchanged.

`ci_scripts/ci_pre_xcodebuild.sh` checks generated framework/config/model inputs and
rejects a local development identity override. Apple manages Cloud signing; these
scripts need no custom signing secrets or personal photos.

Cloud workers have successfully completed model conversion, branding checks and
framework generation. Model downloads use bounded reads, exact size/hash checks and
three retries. The branding audit uses Git file enumeration and does not require
ripgrep. Earlier download and missing-ripgrep failures are resolved.

Keep scripts executable. Do not commit generated Frameworks, DerivedData, model
packages, signing keys, identity overrides, device backups or `.xcode-cloud` environments.

## Archive and TestFlight next steps

Add Release Archive actions for iOS and Mac Catalyst, retaining the Catalyst destination.
Check App Store Connect's existing build numbers before setting Cloud numbering; local
source uses build number 1 and the prior uploads let Xcode manage distribution numbering.
Confirm each archive processes successfully before adding an internal TestFlight group.
External distribution and public release require their own subsequent steps.

The GitHub connection is already configured for `cwallyman/iLightCraft`. Future account
or service-term prompts must be reviewed by the account holder.

## Other verification

Signed local iOS and Mac Catalyst 0.11.0 archives and uploads succeeded. Their ignored
logs are in `LocalVerification/StoreUpload-20261025-v011/`. This is separate from Cloud
Build actions and does not establish TestFlight availability or physical feature acceptance.

Local iOS and Mac Catalyst Release builds passed after the Swift warning cleanup.
The required parent-reference `cargo xtask ci` gate passed before publication, including
fmt, Clippy, HEIF, workspace tests, parity, layers, assets and WASM. Its 165 skips comprise
137 corpus, 20 fonts and eight models. These Rust reference checks are separate from
native runtime acceptance.

References: [first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow),
[GitHub connection](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github),
[custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).
