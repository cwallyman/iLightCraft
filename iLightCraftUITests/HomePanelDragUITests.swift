//
//  HomePanelDragUITests.swift
//  iLightCraftUITests
//

import XCTest

/// HomePanelDragUITests drag the home's Photos panel with real touches on the device, the way a
/// finger would: from the toolbar's empty space, from a toolbar button, and on the grid, both
/// while the grid shows its top and while it is scrolled. Each checks where the panel settles and
/// that no drag moves the app's window. They need the photo library access already granted.
@MainActor
final class HomePanelDragUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// aToolbarDragUpExpandsThePanel catches a drag on the toolbar's empty space that never
    /// reaches the panel and falls through to the window.
    func testAToolbarDragUpExpandsThePanel() {
        let app = launchHome(expanded: false)

        drag(app, from: toolbarSpace(app), by: -320)

        XCTAssertTrue(settles(app, as: "Expanded"))
        assertWindowStayed(app)
    }

    /// aDragStartingOnAToolbarButtonMovesThePanel catches a button or a glass control that keeps
    /// the drag for itself, and a drag that taps the button on the way.
    func testADragStartingOnAToolbarButtonMovesThePanel() {
        let app = launchHome(expanded: false)
        let raw = app.buttons["Show Only RAW Photos"]
        XCTAssertTrue(raw.waitForExistence(timeout: 5))

        drag(app, from: raw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), by: -320)

        XCTAssertTrue(settles(app, as: "Expanded"))
        XCTAssertFalse(raw.isSelected)
        assertWindowStayed(app)
    }

    /// aToolbarDragDownCollapsesThePanel is the expanded panel pulled down by its toolbar.
    func testAToolbarDragDownCollapsesThePanel() {
        let app = launchHome(expanded: true)

        drag(app, from: toolbarSpace(app), by: 360)

        XCTAssertTrue(settles(app, as: "Collapsed"))
        assertWindowStayed(app)
    }

    /// aPullDownOnTheGridAtItsTopCollapsesThePanel is the system sheet's rule: a grid showing
    /// its top hands a downward pull to the panel.
    func testAPullDownOnTheGridAtItsTopCollapsesThePanel() {
        let app = launchHome(expanded: true)

        drag(app, from: gridPoint(app), by: 360)

        XCTAssertTrue(settles(app, as: "Collapsed"))
        assertWindowStayed(app)
    }

    /// scrollingTheGridKeepsThePanelExpanded catches a panel that steals the grid's scrolling:
    /// scrolling down, then partly back up, must leave the panel where it is.
    func testScrollingTheGridKeepsThePanelExpanded() {
        let app = launchHome(expanded: true)

        drag(app, from: gridPoint(app), by: -400)
        XCTAssertTrue(settles(app, as: "Expanded"))

        drag(app, from: gridPoint(app), by: 150)
        XCTAssertTrue(settles(app, as: "Expanded"))
        assertWindowStayed(app)
    }

    /// aDragThatScrollsBackToTheTopThenCollapses is the hand-over halfway through one drag: the
    /// grid scrolls back to its top, then the same finger pulls the panel down.
    func testADragThatScrollsBackToTheTopThenCollapses() {
        let app = launchHome(expanded: true)

        drag(app, from: gridPoint(app), by: -250)
        XCTAssertTrue(settles(app, as: "Expanded"))

        drag(app, from: gridPoint(app, at: 0.3), by: 650)
        XCTAssertTrue(settles(app, as: "Collapsed"))
        assertWindowStayed(app)
    }

    // MARK: Helpers

    private func launchHome(expanded: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-iLightCraftHomePhotos"] + (expanded ? ["-iLightCraftHomeExpanded"] : [])
        app.launch()

        XCTAssertTrue(panel(app).waitForExistence(timeout: 10))
        XCTAssertTrue(settles(app, as: expanded ? "Expanded" : "Collapsed"))
        XCTAssertTrue(app.buttons["Show Only RAW Photos"].waitForExistence(timeout: 10))
        return app
    }

    private func panel(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PhotosPanel"]
    }

    /// settles waits for the panel to report a detent.
    private func settles(_ app: XCUIApplication, as state: String) -> Bool {
        let settled = NSPredicate(format: "value == %@", state)
        let waiter  = XCTNSPredicateExpectation(predicate: settled, object: panel(app))
        return XCTWaiter().wait(for: [waiter], timeout: 3) == .completed
    }

    /// toolbarSpace is a point in the toolbar's empty space, between the Recents / Albums switch
    /// and the RAW button.
    private func toolbarSpace(_ app: XCUIApplication) -> XCUICoordinate {
        app.buttons["Show Only RAW Photos"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -160, dy: 0))
    }

    /// gridPoint is a point on the grid, a fraction of the way down from the toolbar to the
    /// screen's bottom.
    private func gridPoint(_ app: XCUIApplication, at fraction: CGFloat = 0.5) -> XCUICoordinate {
        let toolbar = app.buttons["Show Only RAW Photos"].frame
        let bottom  = app.windows.firstMatch.frame.maxY
        let y       = toolbar.maxY + 40 + (bottom - toolbar.maxY - 80) * fraction

        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: toolbar.midX - 400, dy: y))
    }

    private func drag(_ app: XCUIApplication, from start: XCUICoordinate, by distance: CGFloat) {
        start.press(
            forDuration         : 0.05,
            thenDragTo          : start.withOffset(CGVector(dx: 0, dy: distance)),
            withVelocity        : .default,
            thenHoldForDuration : 0.05
        )
    }

    /// assertWindowStayed catches a drag that fell through to the system and moved the app.
    private func assertWindowStayed(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let frame = app.windows.firstMatch.frame
        XCTAssertEqual(frame.minY, 0, accuracy: 1, "the app's window moved", file: file, line: line)
        XCTAssertEqual(frame.minX, 0, accuracy: 1, "the app's window moved", file: file, line: line)
    }
}
