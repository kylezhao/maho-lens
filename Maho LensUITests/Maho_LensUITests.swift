//
//  Maho_LensUITests.swift
//  Maho LensUITests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import XCTest

/// Drives the demo portrait source through the spells, takes a photo and visits the gallery and
/// settings, saving screenshots to /tmp/maho-screens. Works in the Simulator, which has no camera.
final class Maho_LensUITests: XCTestCase {
    private let screenshotDirectory = URL(fileURLWithPath: "/tmp/maho-screens", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    @MainActor
    func testSpellsCaptureAndGallery() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-demo-source"]
        app.launch()

        let fps = app.staticTexts["fpsLabel"]
        XCTAssertTrue(fps.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 20) { (Double(fps.label) ?? 0) > 0 }, "Preview should be rendering frames")
        sleep(2)
        snapshot(app, "01-preview")

        tapChip(app, "spell-frostVeil")
        sleep(1)
        snapshot(app, "02-frost-veil")

        tapChip(app, "spell-emberVeil")
        XCTAssertTrue(app.sliders["intensitySlider"].waitForExistence(timeout: 3))
        app.sliders["intensitySlider"].adjust(toNormalizedSliderPosition: 0.9)
        sleep(1)
        snapshot(app, "03-ember-veil")

        tapChip(app, "spell-mistBarrier")
        XCTAssertTrue(waitUntil(timeout: 20) { app.staticTexts["fpsLabel"].exists })
        sleep(3) // let segmentation produce a mask
        snapshot(app, "04-mist-barrier")

        tapChip(app, "spell-moonlightMono")
        sleep(1)
        snapshot(app, "05-moonlight-mono")

        let fpsBefore = Double(fps.label) ?? 0
        app.buttons["fpsToggle"].tap()
        let target60 = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "target 60")).firstMatch
        if !target60.waitForExistence(timeout: 5) {
            // Retry once by coordinate in case the first tap landed during a layout change.
            app.buttons["fpsToggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(target60.waitForExistence(timeout: 5), "Dial should switch to the 60 fps target. Texts: \(app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label))")
        sleep(3)
        snapshot(app, "06-fps-60")
        print("Maho Lens UI test: fps at 30 target \(fpsBefore), at 60 target \(fps.label)")

        app.buttons["shutterButton"].tap()
        acceptSystemAlertsIfNeeded()
        XCTAssertTrue(waitUntil(timeout: 20) {
            self.acceptSystemAlertsIfNeeded()
            return app.buttons["shutterButton"].isEnabled && !app.staticTexts["errorLabel"].exists
        })
        sleep(1)
        snapshot(app, "07-after-capture")

        app.buttons["galleryButton"].tap()
        let gallery = app.navigationBars["Transformations"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "Gallery should open")
        sleep(1)
        snapshot(app, "08-gallery")
        gallery.buttons["Done"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !gallery.exists }, "Gallery should close")
        sleep(1) // let the sheet dismissal finish before presenting another

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(waitUntil(timeout: 5) { settingsButton.exists && settingsButton.isHittable }, "Settings button should be back")
        settingsButton.tap()
        let settingsBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsBar.waitForExistence(timeout: 5), "Settings should open")
        sleep(1)
        snapshot(app, "09-settings")
        settingsBar.buttons["Done"].tap()
    }

    /// Spell chips live in a horizontal scroll view; swipe until the one we want can be tapped.
    @MainActor
    private func tapChip(_ app: XCUIApplication, _ identifier: String) {
        let chip = app.buttons[identifier]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(identifier) should exist")
        chip.tap()
    }

    /// Maps where taps land around the top bar, writing findings to /tmp/maho-topbar-probe.txt.
    @MainActor
    func testTopBarControls() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-demo-source"]
        app.launch()
        let fps = app.staticTexts["fpsLabel"]
        XCTAssertTrue(fps.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 20) { (Double(fps.label) ?? 0) > 0 })
        var lines: [String] = []
        let window = app.windows.firstMatch
        lines.append("window=\(window.frame) settings=\(app.buttons["settingsButton"].frame) toggle=\(app.buttons["fpsToggle"].frame) gallery=\(app.buttons["galleryButton"].frame)")

        // 1) Does the settings sheet open from a direct element tap?
        app.buttons["settingsButton"].tap()
        var opened = app.navigationBars["Settings"].waitForExistence(timeout: 3)
        lines.append("element tap settings -> \(opened)")
        if opened { app.navigationBars["Settings"].buttons["Done"].tap(); sleep(1) }

        // 2) Coordinate taps down a column through the settings button.
        let x = app.buttons["settingsButton"].frame.midX
        for y in stride(from: 60.0, through: 120.0, by: 10.0) {
            window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
            opened = app.navigationBars["Settings"].waitForExistence(timeout: 2)
            lines.append("coordinate (\(Int(x)), \(Int(y))) -> settings opened=\(opened)")
            if opened { app.navigationBars["Settings"].buttons["Done"].tap(); sleep(1); break }
        }

        // 3) Does the gallery (bottom) open from the same kind of tap, as a control?
        app.buttons["galleryButton"].tap()
        let galleryOpened = app.navigationBars["Transformations"].waitForExistence(timeout: 3)
        lines.append("element tap gallery -> \(galleryOpened)")
        if galleryOpened { app.navigationBars["Transformations"].buttons["Done"].tap(); sleep(1) }

        // 4) Toggle via element and via coordinate.
        app.buttons["fpsToggle"].tap()
        var switched = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "target 60")).firstMatch.waitForExistence(timeout: 3)
        lines.append("element tap toggle -> \(switched)")
        if !switched {
            let frame = app.buttons["fpsToggle"].frame
            window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            switched = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "target 60")).firstMatch.waitForExistence(timeout: 3)
            lines.append("coordinate tap toggle at \(frame.midX),\(frame.midY) -> \(switched)")
        }
        snapshot(app, "probe-topbar")
        try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/maho-topbar-probe.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(switched, lines.joined(separator: " | "))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    @MainActor
    private func acceptSystemAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for title in ["Allow Full Access", "Add Photos Only", "Allow", "OK"] {
            let button = alert.buttons[title]
            if button.exists { button.tap(); return }
        }
        let buttons = alert.buttons
        if buttons.count > 0 { buttons.element(boundBy: buttons.count - 1).tap() }
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: screenshotDirectory.appendingPathComponent("\(name).png"))
    }
}
