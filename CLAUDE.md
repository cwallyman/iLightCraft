# Unveil

iPad RAW editor (iPadOS 26+): SwiftUI editor shell and panels, UIKit/Metal canvas and system adapters, and a Rust engine in `Engine/` (the vendored LightCraft workspace plus the `Engine/ffi` bridge).

`UnveilApp` is the SwiftUI entry point and presents `ContentView` in a `WindowGroup`. `ContentView` retains an `EditorWorkspace`, which composes one `CanvasView`, `EditorSession` and `EditorDiagnostics` for `EditorView`. `AppDelegate` remains only as a service-startup adapter through `UIApplicationDelegateAdaptor`; there is no custom scene delegate or root hosting controller. SwiftUI owns navigation, the home screen, the editor's toolbar (title menu, zoom pill, Undo/Redo, More menu), the trailing tool rail with its adjust card, and alerts. `EditorCanvas` bridges the stable native view; frame delivery remains `EngineManager` → `FrameSink` → `CanvasView`, outside observable UI state. Low-level lifecycle notifications and the Photos item-provider adapter remain native.

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

Device runs, the golden export and the measurements are in `Docs/Baseline/` (`build-ios.md`,
`device-run.md`, `equivalence.md`, `measurements.md`).

## Rules

- `Engine/crates` is upstream code: change it only with an Apache-2.0 §4(b) notice in the file and an entry in
  `Engine/CHANGES.md`, keep upstream rustfmt for those files (`max_width = 150`, edition 2024), and benchmark
  every change against the `baseline-v0` tag.
- `lightcraft-engine` is used without features; never call `with_default_face_models` or `with_default_denoise_models`.
- Commits are made only by the coordinator: workers never stage, commit or push.
- Branches are `elio/<feature>` (a fix: `elio/<feature>-fix`); a finished feature is merged into `main`
  with a merge commit and its branch deleted.
