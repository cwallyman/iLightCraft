# Unveil

iPad RAW editor (iPadOS 26+): SwiftUI editor shell and panels, UIKit/Metal canvas and system adapters, and a Rust engine in `Engine/` (the vendored LightCraft workspace plus the `Engine/ffi` bridge).

`UnveilApp` is the SwiftUI entry point and presents `ContentView` in a `WindowGroup`. `ContentView` retains an `EditorWorkspace`, which composes one `CanvasView`, `EditorSession` and `EditorDiagnostics` for `EditorView`. `AppDelegate` remains only as a service-startup adapter through `UIApplicationDelegateAdaptor`; there is no custom scene delegate or root hosting controller. SwiftUI owns navigation, the editor's toolbar (title menu, zoom pill, Undo/Redo, More menu), the trailing tool rail with its adjust card, and alerts. `EditorCanvas` bridges the stable native view; frame delivery remains `EngineManager` → `FrameSink` → `CanvasView`, outside observable UI state. The home is the system document launch view (`DocumentLaunch`), whose Files sheet the system browser draws in its own process, plus our PhotoKit library panel (`PhotosPanel`), which `PanelController` moves in UIKit like a sheet. Low-level lifecycle notifications remain native.

## Read first

- Spec: `Docs/Specs/2026-10-09-v0-motore-su-ipad-design.md`
- Plan: `Docs/Plans/2026-10-09-v0-motore-su-ipad.md`
- Style: `CODE_STYLE.md` (comments in English, no em-dashes, `//` at most 2 lines)

## Commands

```bash
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"    # before any cargo command
(cd Engine && cargo test -p unveil-ffi --features test-hooks)
scripts/build-xcframework.sh [--cpu apple-m1]       # engine XCFramework + Config/UnveilEngine.xcconfig
scripts/test-app.sh                                 # app unit tests on the first iPad simulator
```

The `UnveilUITests` scheme drives the home panel with real touches on the iPad; its runner needs a provisioning
profile, which Xcode creates the first time the scheme is run from Xcode with the team signed in.

Device runs, the golden export and the measurements are in `Docs/Baseline/` (`build-ios.md`,
`device-run.md`, `equivalence.md`, `measurements.md`).

## Rules

- `Engine/crates` is upstream code: change it only with an Apache-2.0 §4(b) notice in the file and an entry in
  `Engine/CHANGES.md`, keep upstream rustfmt for those files (`max_width = 150`, edition 2024), and benchmark
  every change against the v0 baseline (commit `fc020cd`, measurements in `Docs/Baseline/`).
- `lightcraft-engine` is used without features; never call `with_default_face_models` or `with_default_denoise_models`.
- Commits are made only by the coordinator: workers never stage, commit or push.
- Branches are `elio/<feature>` (a fix: `elio/<feature>-fix`); a finished feature is merged into `main`
  with a merge commit and its branch deleted.
