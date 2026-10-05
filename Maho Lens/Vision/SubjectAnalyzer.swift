//
//  SubjectAnalyzer.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// What Vision found in a frame.
struct SubjectInfo: @unchecked Sendable {
    /// Largest face as a normalized rect with a top-left origin, in the frame's orientation.
    var faceRect: CGRect?
    /// Person mask (white = person) in the frame's orientation, at the segmentation resolution.
    var mask: CIImage?
    /// True when the mask was synthesized from the face because segmentation was unavailable.
    var maskIsSynthetic = false
    var timestamp: TimeInterval
    var milliseconds: Double
}

/// Runs face detection and person segmentation on a serial queue. Live frames are dropped while a
/// previous analysis is still running, so analysis never backs up the capture pipeline.
final class SubjectAnalyzer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kylezhao.MahoLens.analysis", qos: .userInitiated)
    private var isBusy = false
    private let busyLock = NSLock()

    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let errorLock = NSLock()
    private var _lastError: String?

    /// Most recent Vision error, for the metrics report and tests.
    var lastError: String? {
        errorLock.lock(); defer { errorLock.unlock() }
        return _lastError
    }

    private func record(error: any Error, stage: String) {
        errorLock.lock(); defer { errorLock.unlock() }
        _lastError = "\(stage): \(error.localizedDescription)"
    }

    init(quality: SegmentationQuality = .balanced) {
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        #if targetEnvironment(simulator)
        // The Simulator has no neural-engine runtime; revision 3 fails with "Could not create
        // inference context". Revision 2 is the classic CPU detector and works everywhere.
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision2
        #endif
        setQuality(quality)
    }

    func setQuality(_ quality: SegmentationQuality) {
        queue.async { [self] in
            segmentationRequest.qualityLevel = switch quality {
            case .fast: .fast
            case .balanced: .balanced
            case .accurate: .accurate
            }
        }
    }

    /// Analyzes a live frame unless an analysis is in flight. Returns false when the frame was dropped.
    @discardableResult
    func analyzeIfIdle(_ pixelBuffer: CVPixelBuffer, wantsMask: Bool, wantsFace: Bool, completion: @escaping @Sendable (SubjectInfo) -> Void) -> Bool {
        busyLock.lock()
        if isBusy {
            busyLock.unlock()
            return false
        }
        isBusy = true
        busyLock.unlock()

        queue.async { [self] in
            let info = perform(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]), wantsMask: wantsMask, wantsFace: wantsFace)
            busyLock.lock(); isBusy = false; busyLock.unlock()
            completion(info)
        }
        return true
    }

    /// Analyzes a still image, always running to completion.
    func analyze(_ image: CIImage, wantsMask: Bool = true, wantsFace: Bool = true) async -> SubjectInfo {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
                continuation.resume(returning: perform(handler, wantsMask: wantsMask, wantsFace: wantsFace))
            }
        }
    }

    private func perform(_ handler: VNImageRequestHandler, wantsMask: Bool, wantsFace: Bool) -> SubjectInfo {
        let start = CACurrentMediaTime()
        var info = SubjectInfo(faceRect: nil, mask: nil, timestamp: start, milliseconds: 0)
        // The requests run separately so a segmentation failure (for example in the Simulator, which
        // lacks the neural engine path) does not also discard the face result.
        if wantsFace {
            do {
                try handler.perform([faceRequest])
                if let faces = faceRequest.results, !faces.isEmpty {
                    // Single-person focus: the largest face wins.
                    let largest = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                    info.faceRect = largest.map { CameraGeometry.topLeftRect(fromVisionRect: $0.boundingBox) }
                }
            } catch {
                record(error: error, stage: "face")
            }
        }
        if wantsMask {
            do {
                try handler.perform([segmentationRequest])
                if let observation = segmentationRequest.results?.first {
                    info.mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
                }
            } catch {
                record(error: error, stage: "segmentation")
            }
            if info.mask == nil {
                // No segmentation (Simulator, or an unsupported device): fall back to a soft oval around
                // the face so the Mist Barrier still separates the subject from the background.
                let faceRect = info.faceRect ?? (wantsFace ? nil : detectFace(with: handler))
                if let faceRect {
                    info.mask = Self.syntheticMask(around: faceRect)
                    info.maskIsSynthetic = true
                }
            }
        }
        info.milliseconds = (CACurrentMediaTime() - start) * 1000
        return info
    }

    private func detectFace(with handler: VNImageRequestHandler) -> CGRect? {
        do {
            try handler.perform([faceRequest])
            guard let faces = faceRequest.results, !faces.isEmpty else { return nil }
            let largest = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            return largest.map { CameraGeometry.topLeftRect(fromVisionRect: $0.boundingBox) }
        } catch {
            record(error: error, stage: "face")
            return nil
        }
    }

    /// A head-and-shoulders oval in a 256-wide, 9:16 mask image, white inside and fading to black.
    static func syntheticMask(around faceRect: CGRect, size: CGSize = CGSize(width: 256, height: 455)) -> CIImage {
        let centerX = faceRect.midX * size.width
        // Vision rects use a top-left origin; Core Image's origin is bottom-left.
        let centerY = (1 - faceRect.midY - faceRect.height * 0.35) * size.height
        let radius = max(faceRect.width * size.width, faceRect.height * size.height) * 1.35
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: centerX, y: centerY)
        gradient.radius0 = Float(radius)
        gradient.radius1 = Float(radius * 1.6)
        gradient.color0 = .white
        gradient.color1 = .black
        let oval = gradient.outputImage ?? CIImage(color: .white)
        // Stretch vertically so the oval covers shoulders and torso below the face.
        let stretch = CGAffineTransform(translationX: centerX, y: centerY).scaledBy(x: 1, y: 1.7).translatedBy(x: -centerX, y: -centerY)
        return oval.transformed(by: stretch).cropped(to: CGRect(origin: .zero, size: size))
    }
}
