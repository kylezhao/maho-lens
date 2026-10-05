//
//  CaptureSettings.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreGraphics
import Foundation

/// The preview frame-rate target. The assignment accepts 25+ at 30 and 50+ at 60.
enum FrameRateSetting: Int, CaseIterable, Identifiable, Codable, Sendable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) fps" }

    /// Lowest measured preview rate that still passes.
    var minimumAcceptable: Double {
        switch self {
        case .fps30: 25
        case .fps60: 50
        }
    }
}

enum CameraPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case front
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: String(localized: "Front")
        case .back: String(localized: "Back")
        }
    }

    mutating func flip() {
        self = self == .front ? .back : .front
    }
}

/// Person segmentation quality. Faster levels give lower-resolution masks.
enum SegmentationQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast
    case balanced
    case accurate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .balanced: String(localized: "Balanced")
        case .accurate: String(localized: "Accurate")
        }
    }
}

struct CaptureConfiguration: Equatable, Sendable {
    var position: CameraPosition
    var frameRate: FrameRateSetting
}

/// Picks a capture format: must support the frame rate, prefers the tallest frame up to the limit.
/// Abstracted over a protocol so the policy is unit-testable without `AVCaptureDevice.Format`.
protocol FormatCandidate {
    var frameHeight: Int { get }
    var frameWidth: Int { get }
    var maximumFrameRate: Double { get }
    var isBinned: Bool { get }
}

enum FormatSelector {
    static func select<F: FormatCandidate>(from formats: [F], frameRate: Int, maximumHeight: Int = 1080) -> F? {
        let capable = formats.filter { $0.maximumFrameRate >= Double(frameRate) && $0.frameHeight <= maximumHeight && $0.frameHeight >= 480 }
        guard !capable.isEmpty else {
            // Fall back to anything that supports the rate, even if it is larger or smaller.
            return formats.filter { $0.maximumFrameRate >= Double(frameRate) }
                .min { abs($0.frameHeight - maximumHeight) < abs($1.frameHeight - maximumHeight) }
        }
        return capable.max { lhs, rhs in
            if lhs.frameHeight != rhs.frameHeight { return lhs.frameHeight < rhs.frameHeight }
            if lhs.isBinned != rhs.isBinned { return lhs.isBinned && !rhs.isBinned }
            return lhs.maximumFrameRate < rhs.maximumFrameRate
        }
    }
}

/// Coordinate conversions between the portrait preview and the capture device.
enum CameraGeometry {
    /// Maps a normalized point in the upright, possibly mirrored, portrait frame (origin top-left) to
    /// `AVCaptureDevice` point-of-interest space, whose origin is the top-left of the landscape sensor
    /// image and (1, 1) its bottom-right. Portrait frames are the sensor image rotated 90° clockwise.
    static func devicePoint(fromPortraitPoint point: CGPoint, mirrored: Bool) -> CGPoint {
        let x = mirrored ? 1 - point.x : point.x
        let y = point.y
        return CGPoint(x: min(1, max(0, y)), y: min(1, max(0, 1 - x)))
    }

    /// Converts a Vision normalized rect (origin bottom-left) to a top-left-origin rect.
    static func topLeftRect(fromVisionRect rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Maps a normalized top-left-origin rect in the frame to view coordinates for an aspect-fill preview.
    static func viewRect(for normalized: CGRect, frameSize: CGSize, viewSize: CGSize) -> CGRect {
        guard frameSize.width > 0, frameSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let drawnSize = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        let offset = CGPoint(x: (viewSize.width - drawnSize.width) / 2, y: (viewSize.height - drawnSize.height) / 2)
        return CGRect(
            x: offset.x + normalized.minX * drawnSize.width,
            y: offset.y + normalized.minY * drawnSize.height,
            width: normalized.width * drawnSize.width,
            height: normalized.height * drawnSize.height
        )
    }
}
