# SwiftUI Editor Migration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. No commits.

**Goal:** Migrate the existing editor shell to SwiftUI without changing the rendering pipeline or adding screens.

**Architecture:** SwiftUI owns navigation, toolbar menus, the adjustment inspector, empty state and alerts. A stable UIViewRepresentable hosts the existing CanvasView. UIKit remains in the application lifecycle, system Photos picker adapter and low-level canvas/input code.

**Tech Stack:** Swift 6, iPadOS 26, SwiftUI, UIKit, Metal, existing Rust FFI.

**Spec:** User-approved migration table in this conversation; existing editor behavior is the compatibility contract.

## Global Constraints

- Preserve all existing working-tree changes and do not commit.
- No visual redesign, library screens, engine changes or per-frame SwiftUI state.
- One named responsibility per file, following CODE_STYLE.md.
- Keep Files security-scoped imports and Photos current/RAW representation and staging cleanup.

## Review Focus

- Inspector open/close must retain the canvas and its GPU resources.
- Failed imports must retain the current photo and release Photos staging files.
- Alerts must appear above the compact inspector.
- Picker cancellation must not start an import; duplicate imports must be rejected.
- Launch diagnostics, panel selection and background/foreground refresh must still work.

## Task 1: Presentation state and import lifecycle

Files: create Views/Editor/EditorSession.swift and Models/Editor/EditorAlert.swift; add EditorSessionTests and a controlled Photos loader fake.

- [x] Test inspector gating/selection, Photos failure cleanup and concurrent-import rejection.
- [x] Implement observable presentation state with `showPanel`, `importLibraryPhoto` and `dismissAlert`.
- [x] Compile the focused tests. Runtime execution is unavailable: no installed simulator device/runtime.

## Task 2: SwiftUI shell and native adapters

Files: replace EditorViewController with EditorView; create EditorCanvas, EditorAlertPresenter, EditorUnavailableView and PhotoLibraryPicker; migrate OpenPhotoButton and DiagnosticsMenu; extract EditorDiagnostics; adapt SceneDelegate.

- [x] Preserve CanvasView instance identity across state changes and only reset zoom for a new PhotoID.
- [x] Use NavigationStack, toolbar, inspector, fileImporter, sheet and alert.
- [x] Retain native Photos configuration and all existing diagnostic actions.
- [x] Adapt hosting integration tests for compact/regular inspector, canvas identity/hit testing and error presentation.
- [x] Build app and tests without signing. No runnable test destination exists.

## Task 3: Documentation and verification

- [x] Update current architecture references in README, CLAUDE.md and CODE_STYLE.md.
- [x] Review changes against the pre-migration working-tree snapshot. Independent review found no critical or important regression; documentation and formatting findings were corrected.
- [x] Record build/test evidence and runtime verification limits without claiming a performance improvement.

## Execution Notes

- Baseline source and tests are preserved under `/tmp/unveil-swiftui-before` for migration-only review.
- CoreSimulator reports no available devices. Runtime tests cannot run until an iOS simulator runtime/device exists; compile both device app and simulator test targets instead.
- Work stays in the current checkout to preserve the user's uncommitted editor work. No branch, staging or commit operations.
- New session tests were compiled first and failed because EditorSession did not exist, then compiled successfully after implementation. This is compilation evidence only, not an executed test pass.
- Verified `xcodebuild build-for-testing -project Unveil.xcodeproj -scheme Unveil -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/unveil-swiftui-build CODE_SIGNING_ALLOWED=NO -quiet` and a Release build with destination `generic/platform=iOS` and DerivedData `/tmp/unveil-swiftui-device`.
- Engine, FrameSink, CanvasView, adjustment algorithms and existing unrelated edits match the pre-migration snapshot. No claim of improved frame time or memory use is made without device profiling.
- Review left baseline diagnostic-gradient occlusion and Files-import concurrency unchanged; changing those behaviors is outside this migration.

## Follow-up: SwiftUI App Entry and ContentView

The user requested the conventional SwiftUI root after the initial editor-shell migration.

- `UnveilApp: App` is now the sole `@main`, with a `WindowGroup` containing `ContentView`.
- `AppDelegate` remains a `UIApplicationDelegateAdaptor` for process service startup; `SceneDelegate` and its Info.plist registration are removed.
- `ContentView` retains `EditorWorkspace` in State. Composition waits for a nonzero initial window size and uses the local display scale, capped at 2560 pixels. Resizing does not recreate the workspace.
- `EditorWorkspace` owns scene dependencies and the activation-refresh observer. `EditorLaunchRunner` preserves the launch diagnostics and measurement commands independently of view updates.
- The simulator test target and device Release target are compiled again. Runtime launch and interaction checks still require an installed simulator or device.
