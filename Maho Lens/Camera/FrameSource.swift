//
//  FrameSource.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation

/// One video frame, already upright for portrait display.
struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let isMirrored: Bool

    var size: CGSize {
        CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    }
}

/// A still captured from the source, upright, ready for the spell renderer.
struct CapturedPhoto: @unchecked Sendable {
    let image: CIImage
}

enum CameraError: LocalizedError, Equatable {
    case noCamera
    case accessDenied
    case configurationFailed(String)
    case captureFailed(String)
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .noCamera: String(localized: "No camera is available on this device.")
        case .accessDenied: String(localized: "Camera access is off. Allow it in Settings to cast spells.")
        case .configurationFailed(let detail): String(localized: "The camera could not be configured.") + " " + detail
        case .captureFailed(let detail): String(localized: "The photo could not be taken.") + " " + detail
        case .photoLibraryDenied: String(localized: "Photo library access is off, so the photo was kept inside Maho Lens only.")
        }
    }
}

/// Produces frames for the preview: the real camera on a device, a demo portrait in the Simulator.
protocol FrameSource: AnyObject, Sendable {
    /// Called on the source's own queue for every frame.
    var onFrame: ((VideoFrame) -> Void)? { get set }
    /// Human-readable description such as "Front camera 1920×1080 @60".
    var descriptor: String { get }
    var isMirrored: Bool { get }
    func configure(_ configuration: CaptureConfiguration) async throws
    func start()
    func stop()
    func setFrameRate(_ frameRate: FrameRateSetting) async throws
    /// Point in the upright frame, normalized, origin top-left.
    func focus(at point: CGPoint)
    func capturePhoto() async throws -> CapturedPhoto
}
