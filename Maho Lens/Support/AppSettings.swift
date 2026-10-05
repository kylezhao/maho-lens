//
//  AppSettings.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let frameRate = "frameRate"
        static let cameraPosition = "cameraPosition"
        static let segmentationQuality = "segmentationQuality"
        static let showMetrics = "showMetrics"
        static let saveToPhotoLibrary = "saveToPhotoLibrary"
    }

    private let defaults: UserDefaults

    var frameRate: FrameRateSetting { didSet { defaults.set(frameRate.rawValue, forKey: Keys.frameRate) } }
    var cameraPosition: CameraPosition { didSet { defaults.set(cameraPosition.rawValue, forKey: Keys.cameraPosition) } }
    var segmentationQuality: SegmentationQuality { didSet { defaults.set(segmentationQuality.rawValue, forKey: Keys.segmentationQuality) } }
    var showMetrics: Bool { didSet { defaults.set(showMetrics, forKey: Keys.showMetrics) } }
    var saveToPhotoLibrary: Bool { didSet { defaults.set(saveToPhotoLibrary, forKey: Keys.saveToPhotoLibrary) } }

    /// Forces the demo portrait even when a camera exists. Set by the `-demo-source` launch argument.
    let forcesDemoSource: Bool

    init(defaults: UserDefaults = .standard, arguments: [String] = CommandLine.arguments) {
        self.defaults = defaults
        frameRate = FrameRateSetting(rawValue: defaults.integer(forKey: Keys.frameRate)) ?? .fps30
        cameraPosition = defaults.string(forKey: Keys.cameraPosition).flatMap(CameraPosition.init(rawValue:)) ?? .front
        segmentationQuality = defaults.string(forKey: Keys.segmentationQuality).flatMap(SegmentationQuality.init(rawValue:)) ?? .balanced
        showMetrics = defaults.object(forKey: Keys.showMetrics) as? Bool ?? true
        saveToPhotoLibrary = defaults.object(forKey: Keys.saveToPhotoLibrary) as? Bool ?? true
        forcesDemoSource = arguments.contains("-demo-source")
    }
}
