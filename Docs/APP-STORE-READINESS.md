# iLightCraft App Store preparation

Last updated: 2026-10-25. This is preparation, not submission approval or an App Store validation result.

## Current upload — 2026-10-25

The user selected version **0.11.0** with the current engine; upstream engine updates
are deferred to the next version. Fresh signed iOS and Mac Catalyst archives succeeded,
and both App Store Connect uploads reported `Upload succeeded` / `EXPORT SUCCEEDED`.
The source build number was 1; automatic distribution build-number management was enabled.
Logs and archives are in `LocalVerification/StoreUpload-20261025-v011/` (ignored).
Apple's subsequent processing, TestFlight availability, App Review and public release
were not verified. No existing device app/library was replaced by these uploads.

Earlier 0.14.0 upload attempts were interrupted without reporting success after the
user selected 0.11.0; do not use those earlier archives for this release.
See [Xcode Cloud setup](XCODE-CLOUD.md): both iOS and Mac Catalyst Build actions passed at `303faf0`. Automatic Archive/TestFlight delivery is not yet configured.

## Identity and branding

- Native project: `iLightCraft.xcodeproj`, app/scheme/module/executable `iLightCraft`.
- Source/test folders: `iLightCraft`, `iLightCraftTests`, `iLightCraftUITests`.
- Engine bridge: `ilightcraft-ffi`, library `ilightcraft_ffi`, module/framework `iLightCraftEngine`.
- Internal bridge commands use `ilightcraft.*`; new Photos adjustments use `com.cwallyman.iLightCraft.develop`.
- Release bundle ID: `com.cwallyman.iLightCraft`, explicitly approved by the user on 2026-10-22. The App Store Connect record was used for the successful 0.11.0 uploads.
- Team: `D58RZM4K8N`, verified against the current local development profile. Signed local distribution archives and uploads subsequently succeeded.
- User confirmed on 2026-10-22 that existing test installs and libraries must be preserved. Old test installs retain their identity via ignored `Config/DevelopmentIdentity.xcconfig`, used only by the Debug helper. Changing an app identity creates a separate sandbox; a new Store install will need a user-driven portable backup/recovery transfer from the test app. Do not uninstall the existing test app before preserving its library.

The product code/config/scripts audit allows the original name only in read-only `LegacyEditCompatibility.swift` and bundled legal notices. The adapter accepts old Photos adjustment identifiers/envelopes and migrates the preferred-library setting; new writes use iLightCraft. Upstream copyright/modification notices, provenance URLs, git history and historical baseline documents are preserved. Generated old build directories are not shipping source and have not been relabeled as new evidence.

Run `python3 scripts/audit-branding.py` for the static source audit. The helper neither launches apps nor runs tests. Old FFI command names and diagnostic launch flags are intentionally not aliases; use the renamed scripts.

Branding rechecked on 2026-10-25: the audit now also checks the display/bundle names,
Xcode scheme/product references, project bundle IDs and Rust bridge identity. Existing
iOS and Mac archive metadata still names the app/executable `iLightCraft` with ID
`com.cwallyman.iLightCraft`; these are the earlier archives, not fresh builds.
The parent workspace README now identifies iLightCraft first and marks the retained
upstream documentation as reference. The fallback wrapper's remaining error/alert
titles also use iLightCraft. No app was installed, launched or uploaded in this recheck.

## Release packaging changes

- Added `PrivacyInfo.xcprivacy`: no tracking/collected-data declarations; app-only defaults (`CA92.1`), container/user-selected file metadata (`C617.1`, `3B52.1`) and elapsed-time measurement (`35F9.1`). These reflect inspected local app behavior, not an independent network/privacy audit.
- Debug disk-space inspection is not compiled into Release. Re-audit APIs/dependencies before submission and generate Xcode's final privacy report.
- Bundled the upstream notices and Apache/MIT license texts verbatim, accessible through Settings > Licenses & Credits. Additional dependency/license review remains.
- Photos permission text now describes saving on Back as well as explicit save.
- Removed the unprovisioned increased-memory entitlement; current local installs already lacked this entitlement. Test large RAW workloads with normal OS memory limits.
- Retained Mac sandbox and selected-file/Photos access; enabled hardened runtime for Release, disabled the app's Release debug dylib.
- The 1024px app icon has no alpha channel. App Store screenshots, accessibility and all device appearances remain unverified.

Unsigned archive commands (no upload, installation or launch):

```sh
scripts/build-xcframework.sh
scripts/archive-apple-local.sh ios
scripts/archive-apple-local.sh mac
```

These scripts deliberately do not use local Debug identity overrides or request automatic provisioning changes. Archive output is `LocalVerification/Archives/` inside this checkout. Signed distribution archives and uploads subsequently succeeded as recorded above; Apple processing and submission approval remain unverified.

## Remaining before submission

- Confirm uploaded builds finish processing in App Store Connect and configure Cloud Archive/TestFlight delivery. Current Mac engine coverage is Apple Silicon only.
- Complete physical regression acceptance: RAW/HDR camera support, Photos save/reopen/revert/conflict recovery, undo/persistence/export, masks/AI quality, adaptive layouts/accessibility and library backup/recovery. Saved tests and no-launch builds do not establish runtime acceptance.
- Review bundled/transitively linked dependencies and downloaded models, redistribution terms and required notices; verify final archive contents and privacy aggregation.
- Prepare public privacy policy/support URLs, App Privacy questionnaire, age rating, content rights/export-compliance answers, description, screenshots and review notes. Verify model-download hosts and data handling against the privacy policy. Do not invent store answers from build success.
- Remove or clearly disable incomplete workflows in the shipping UI; CloudKit is deferred and must not be advertised as supported. The feature acceptance record remains in `MISSING-FEATURES.md` and `NEXT-STEPS.md`.
- Perform TestFlight testing and Apple's archive validation before release. Nothing was uploaded in this task.

References checked on 2026-10-21: [distribution preparation](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [privacy reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), [adding privacy entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

## Verification for this change

- Static branding audit: passed; plist/project syntax and shell syntax checks passed.
- Renamed engine XCFramework: release build passed for iOS device, iOS simulator and Mac Catalyst.
- Unsigned iOS Release archive: **ARCHIVE SUCCEEDED**.
- Unsigned Mac Catalyst Release archive: **ARCHIVE SUCCEEDED**.
- Inspected both final archives: name/executable `iLightCraft`, ID `com.cwallyman.iLightCraft`, privacy manifest and legal notices present at the platform-appropriate resource locations.
- App icon 1024px PNG: no alpha channel.
- Local evidence: parent workspace `LocalVerification/branding-20261021/`, including archive logs and `archive-inspection.json`. Existing compiler warnings remain (unused capture, redundant typed-error cast/unsafe annotation, plus toolchain linker/App Intents warnings); archives passed despite them.
- Compatibility regression tests saved in `iLightCraftTests/BrandCompatibilityTests.swift`, unrun. No suites, benchmarks, runtime launches, device installation, signing submission validation or uploads performed for this branding change. Existing device installations and libraries are unchanged.
