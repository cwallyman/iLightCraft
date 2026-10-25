//
//  EditorViewTests.swift
//  iLightCraftTests
//

import Metal
import SwiftUI
import Testing
import UIKit
@testable import iLightCraft

@Suite(.serialized, .exclusiveWindow)
@MainActor
struct EditorViewTests {

    /// dockedCardReservesPhotoSpace checks actual hosted canvas bounds on phone and tablet layouts.
    /// Opening and closing the dock must resize the same Metal view without covering its center.
    @Test(arguments: [true, false])
    func dockedCardReservesPhotoSpace(compact: Bool) async throws {
        let fixture = try Fixture(compact: compact)
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        let size = fixture.canvas.bounds.size

        let expectsBottom = UIDevice.current.userInterfaceIdiom == .phone
        fixture.session.showPanel(.color)
        try await waitUntil(seconds: 3) {
            expectsBottom ? fixture.canvas.bounds.height < size.height - 200
                : fixture.canvas.bounds.width < size.width - 200
        }
        #expect(fixture.session.isCardOpen)
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(fixture.canvasReceivesCenterTouch)
        if expectsBottom {
            #expect(abs(fixture.canvas.bounds.width - size.width) < 1)
            #expect(fixture.canvas.bounds.height > size.height * 0.45)
        } else {
            #expect(abs(fixture.canvas.bounds.height - size.height) < 1)
            #expect(fixture.canvas.bounds.width > 0)
        }

        fixture.session.select(.move)
        try await waitUntil(seconds: 3) { fixture.canvas.bounds.size == size }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
    }

    /// A tool panel must reserve canvas width, not cover or recreate its Metal view.
    @Test
    func anInfoToolReservesTheRightSideOnTabletButNotPhone() async throws {
        let baseline = try Fixture()
        defer { baseline.window.isHidden = true }
        try await waitUntil(seconds: 3) { !baseline.canvas.bounds.isEmpty }
        let fullSize = baseline.canvas.bounds.size
        let tool = try Fixture(initialDockTool: .info)
        defer { tool.window.isHidden = true }
        try await waitUntil(seconds: 3) { !tool.canvas.bounds.isEmpty }
        #expect(findCanvas(in: tool.host.view) === tool.canvas)
        if UIDevice.current.userInterfaceIdiom == .phone {
            #expect(abs(tool.canvas.bounds.width - fullSize.width) < 1)
        } else {
            #expect(tool.canvas.bounds.width < fullSize.width - 250)
            #expect(abs(tool.canvas.bounds.height - fullSize.height) < 1)
        }
    }

    /// touchingThePhotoKeepsTheDockOpen allows panning, zooming and before/after while editing.
    @Test
    func touchingThePhotoKeepsTheDockOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        fixture.session.showPanel(.light)
        try await Task.sleep(for: .milliseconds(300))
        fixture.canvas.onSingleTap?()
        fixture.canvas.touchesBegan([], with: nil)
        #expect(fixture.session.isCardOpen)
    }

    /// adjustmentFailureIsVisibleWhileCardIsOpen checks that the card does not hide an editing
    /// error. Closing the alert clears the model while leaving the card open.
    @Test
    func adjustmentFailureIsVisibleWhileCardIsOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        fixture.session.showPanel(.light)
        try await Task.sleep(for: .milliseconds(500))

        fixture.engine.failNextSet = .engine("Adjustment failed")
        await fixture.model.drag(.exposure, to: 1)
        try await waitUntil(seconds: 3) {
            findAlert(in: fixture.host)?.message == "Adjustment failed"
        }
        #expect(fixture.session.isCardOpen)

        fixture.session.dismissAlert()
        try await waitUntil(seconds: 3) { findAlert(in: fixture.host) == nil }
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.session.isCardOpen)
    }

    /// A second error raised while the first alert is on screen is presented once the first is dismissed.
    @Test
    func aSecondAlertIsPresentedAfterTheFirstIsDismissed() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }

        fixture.session.show(EditorAlert(title: "Diagnostics", message: "first"))
        try await waitUntil(seconds: 3) { findAlert(in: fixture.host)?.message == "first" }
        fixture.session.show(EditorAlert(title: "Diagnostics", message: "second"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(findAlert(in: fixture.host)?.message == "first")

        // UIKit takes the alert down as it does on a tap on OK, and SwiftUI reports the dismissal.
        findAlert(in: fixture.host)?.presentingViewController?.dismiss(animated: true)
        try await waitUntil(seconds: 5) { findAlert(in: fixture.host)?.message == "second" }
        #expect(fixture.session.presentedAlert?.message == "second")
    }

    /// An editing error raised while a session alert is up takes priority in `presentedAlert` but
    /// waits behind the alert on screen, and is presented once that one is dismissed.
    @Test
    func anEditingErrorRaisedUnderASessionAlertIsPresentedAfterIt() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }

        fixture.session.show(EditorAlert(title: "Diagnostics", message: "session"))
        try await waitUntil(seconds: 3) { findAlert(in: fixture.host)?.message == "session" }
        fixture.engine.failNextOpen = .engine("editing")
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/other.RAF"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(findAlert(in: fixture.host)?.message == "session")

        findAlert(in: fixture.host)?.presentingViewController?.dismiss(animated: true)
        try await waitUntil(seconds: 5) { findAlert(in: fixture.host)?.message == "editing" }
        #expect(fixture.session.alert == nil)
    }

    /// aDragReevaluatesOnlyItsOwnRow counts slider body runs while the model takes drag values:
    /// only the dragged control's row runs again, although all five pages stay alive.
    @Test
    func aDragReevaluatesOnlyItsOwnRow() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        fixture.session.showPanel(.light)
        try await Task.sleep(for: .milliseconds(500))
        AdjustmentSlider.bodyRuns = [:]

        for step in 1 ... 5 {
            await fixture.model.drag(.exposure, to: Double(step) / 10)
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(AdjustmentSlider.bodyRuns[.exposure, default: 0] > 0)
        #expect(
            AdjustmentSlider.bodyRuns.keys.allSatisfy { $0 == .exposure },
            "body runs per row: \(AdjustmentSlider.bodyRuns)"
        )
    }

    /// aDraftHistogramRepaintsTheOpenCardInPlace delivers two draft histograms, which share one view
    /// identity, and checks the card's pixels change with each: the plot redraws, it is not just
    /// re-evaluated. A third snapshot with nothing new measures the noise the comparison must stand out from.
    @Test
    func aDraftHistogramRepaintsTheOpenCardInPlace() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        fixture.session.showPanel(.light)
        try await Task.sleep(for: .milliseconds(500))

        func deliverDraft(generation: UInt64, peakBin: Int) async throws {
            var bins = [UInt32](repeating: 0, count: 256)
            bins[peakBin] = 1_000
            let histogram = FrameHistogram(
                red         : bins,
                green       : bins,
                blue        : bins,
                luma        : bins,
                total       : 1_000,
                clippedLow  : [0, 0, 0],
                clippedHigh : [0, 0, 0],
                generation  : generation,
                isDraft     : true
            )
            let pixels = [UInt8](repeating: 9, count: 4 * 4 * 4)

            pixels.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }

                fixture.engine.frames.receive(
                    rgba       : base,
                    width      : 4,
                    height     : 4,
                    stride     : 16,
                    generation : generation,
                    isDraft    : true,
                    histogram  : histogram
                )
            }
            try await waitUntil(seconds: 3) { fixture.model.histogram?.generation == generation }
            try await Task.sleep(for: .milliseconds(300))
        }

        func snapshot() -> [UInt8] {
            let image = UIGraphicsImageRenderer(bounds: fixture.window.bounds).image { _ in
                fixture.window.drawHierarchy(in: fixture.window.bounds, afterScreenUpdates: true)
            }
            let data = image.cgImage?.dataProvider?.data

            return data.map { Array(UnsafeBufferPointer(start: CFDataGetBytePtr($0), count: CFDataGetLength($0))) } ?? []
        }

        func differences(_ a: [UInt8], _ b: [UInt8]) -> Int {
            zip(a, b).filter { $0 != $1 }.count
        }

        try await deliverDraft(generation: 1_000, peakBin: 60)
        let first = snapshot()
        try await deliverDraft(generation: 1_001, peakBin: 190)
        let second = snapshot()
        try await Task.sleep(for: .milliseconds(300))
        let again = snapshot()

        let changed = differences(first, second)
        let noise   = differences(second, again)

        #expect(!first.isEmpty && first.count == second.count)
        #expect(changed > 1_000 && changed > 10 * noise, "changed \(changed) bytes, noise \(noise)")
    }

    /// theCardHugsItsRowsAndScrollsWhenTheyDoNotFit measures the card offered 780 pt (an iPad Air
    /// in landscape, about): at the default text size it is shorter (it hugs the Light rows), at
    /// an accessibility size, or offered less (an iPad mini), it fills the space and its rows scroll.
    @Test
    func theCardHugsItsRowsAndScrollsWhenTheyDoNotFit() {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 1024
        )

        func height(at textSize: DynamicTypeSize, offered: CGFloat) -> CGFloat {
            let card = AdjustCard(viewModel: model, group: .constant(.light), clipping: .constant([]))
                .dynamicTypeSize(textSize)

            return UIHostingController(rootView: card)
                .sizeThatFits(in: CGSize(width: 340, height: offered))
                .height
        }

        #expect(height(at: .large, offered: 780) < 780)
        #expect(height(at: .large, offered: 680) == 680)
        #expect(height(at: .accessibility3, offered: 780) == 780)
    }

    /// compactCardFitsPhone checks the real SwiftUI layout at small phone widths and short heights.
    @Test
    func compactCardFitsPhone() {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 1024
        )
        for width: CGFloat in [296, 351, 378] {
            let card = AdjustCard(
                viewModel     : model,
                group         : .constant(.light),
                clipping      : .constant([]),
                width         : width,
                isCompact     : true,
                histogramHeight: 48
            )
            let size = UIHostingController(rootView: card)
                .sizeThatFits(in: CGSize(width: width, height: 280))
            #expect(size.width <= width + 1)
            #expect(size.height <= 281)
            #expect(size.height > 100)
        }
    }

    @Test
    func miniHistogramKeepsItsHeight() {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 1024
        )
        let plot = HistogramView(
            viewModel          : model,
            clipping           : .constant([]),
            fixedPlotHeight    : 48,
            showsCaptureSummary: false
        )
        let size = UIHostingController(rootView: plot).sizeThatFits(in: CGSize(width: 330, height: 400))
        #expect(abs(size.height - 48) < 1)
        #expect(abs(size.width - 330) < 1)
    }

    /// theHistogramPlotIsThreeToOne measures the histogram offered the card's inner width: its
    /// height is a third of it, with or without a histogram yet.
    @Test
    func theHistogramPlotIsThreeToOne() {
        let model = EditorViewModel(
            engine        : FakeEngine(),
            importer      : FakeImporter(),
            previewPixels : 1024
        )
        let plot  = HistogramView(viewModel: model, clipping: .constant([]))
        let size  = UIHostingController(rootView: plot).sizeThatFits(in: CGSize(width: 308, height: 1000))

        #expect(abs(size.width / size.height - 3) < 0.05, "plot measures \(size)")
    }

    /// openingPhotoKeepsCanvas keeps the canvas attached even before an import (the home, not
    /// the editor, covers that state). Without a photo the Adjust tool does not open the card.
    @Test
    func openingPhotoKeepsCanvas() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        try await waitUntil(seconds: 3) { !fixture.canvas.bounds.isEmpty }

        fixture.session.showPanel(.light)
        #expect(!fixture.session.isCardOpen)

        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
    }

    /// canvasSurvivesHomeAndBackWithTheCardClosed hosts the whole workspace: going home and back
    /// keeps the one canvas, and with the card closed it receives a touch at its center.
    @Test
    func canvasSurvivesHomeAndBackWithTheCardClosed() async throws {
        let fixture = try Fixture(hostsWorkspace: true)
        defer { fixture.window.isHidden = true }
        await fixture.session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }

        fixture.session.goHome()
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.canvas.window === fixture.window)

        await fixture.session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(!fixture.session.isCardOpen)
    }

    private func findCanvas(in view: UIView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }

        for subview in view.subviews {
            if let canvas = findCanvas(in: subview) { return canvas }
        }

        return nil
    }

    private func findAlert(in controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController { return alert }
        if let presented = controller.presentedViewController,
           let alert = findAlert(in: presented)
        { return alert }

        for child in controller.children {
            if let alert = findAlert(in: child) { return alert }
        }

        return nil
    }

    @MainActor
    private struct Fixture {

        let engine : FakeEngine
        let model  : EditorViewModel<FakeEngine, FakeImporter>
        let session: EditorSession<FakeEngine, FakeImporter, PhotoLibraryLoader>
        let canvas : CanvasView
        // AnyView: one fixture hosts either the editor or the whole workspace, chosen at run time.
        let host   : UIHostingController<AnyView>
        let window : UIWindow

        init(hostsWorkspace: Bool = false, compact: Bool = false, initialDockTool: EditorDockTool? = nil) throws {
            let engine = FakeEngine()
            let model = EditorViewModel(
                engine        : engine,
                importer      : FakeImporter(),
                previewPixels : 1024
            )
            let session = EditorSession(viewModel: model, libraryLoader: PhotoLibraryLoader())
            let canvas = CanvasView(
                frames : engine.frames,
                device : try #require(MTLCreateSystemDefaultDevice())
            )
            let diagnostics = EditorDiagnostics(
                engine            : engine,
                viewModel         : model,
                possibleTearCount : { [weak canvas] in canvas?.possibleTearCount ?? 0 },
                present           : { [weak session] in session?.show($0) }
            )
            let root = hostsWorkspace
                ? AnyView(WorkspaceView(
                    session       : session,
                    canvas        : canvas,
                    diagnostics   : diagnostics,
                    launchOptions : MeasurementLaunchOptions(arguments: [])
                ))
                : AnyView(EditorView(session: session, canvas: canvas, diagnostics: diagnostics, initialDockTool: initialDockTool))
            let host = UIHostingController(rootView: AnyView(
                root
                    .environment(\.horizontalSizeClass, compact ? .compact : .regular)
                    .frame(width: compact ? 390 : 1024, height: compact ? 700 : 768)
            ))
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            self.engine  = engine
            self.model   = model
            self.session = session
            self.canvas  = canvas
            self.host    = host
            self.window  = window
        }

        var canvasReceivesCenterTouch: Bool {
            guard !canvas.bounds.isEmpty else { return false }

            let center = canvas.convert(
                CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY),
                to: window
            )
            return window.hitTest(center, with: nil) === canvas
        }
    }
}
