//
//  DemoFrameSource.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreImage
import CoreVideo
import Foundation
import QuartzCore

/// Frame source for the Simulator and UI tests: a bundled portrait drifting with a slow
/// Ken Burns move, rendered into BGRA pixel buffers at the requested frame rate.
final class DemoFrameSource: FrameSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kylezhao.MahoLens.demo", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let portrait: CIImage
    private let outputSize: CGSize
    private var pool: CVPixelBufferPool?
    private var timer: DispatchSourceTimer?
    private var frameRate: FrameRateSetting = .fps30
    private var startTime = CACurrentMediaTime()

    var onFrame: ((VideoFrame) -> Void)?
    private(set) var descriptor = "Demo portrait"
    let isMirrored = false

    init(portrait: CIImage, outputSize: CGSize = CGSize(width: 1080, height: 1920)) {
        self.portrait = portrait
        self.outputSize = outputSize
    }

    static func bundled() -> DemoFrameSource? {
        guard let url = Bundle.main.url(forResource: "demo-portrait", withExtension: "jpg"),
              let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        return DemoFrameSource(portrait: image)
    }

    func configure(_ configuration: CaptureConfiguration) async throws {
        frameRate = configuration.frameRate
        descriptor = "Demo portrait \(Int(outputSize.width))×\(Int(outputSize.height)) @\(frameRate.rawValue) (Simulator)"
        var poolRef: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &poolRef)
        pool = poolRef
    }

    func start() {
        queue.async { [self] in
            timer?.cancel()
            startTime = CACurrentMediaTime()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate.rawValue), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.emitFrame() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func setFrameRate(_ frameRate: FrameRateSetting) async throws {
        self.frameRate = frameRate
        descriptor = "Demo portrait \(Int(outputSize.width))×\(Int(outputSize.height)) @\(frameRate.rawValue) (Simulator)"
        stop()
        start()
    }

    func focus(at point: CGPoint) {}

    func capturePhoto() async throws -> CapturedPhoto {
        CapturedPhoto(image: currentImage(at: CACurrentMediaTime()))
    }

    // MARK: - Frames

    /// The portrait, aspect-filled into the output size with a gentle zoom and drift.
    func currentImage(at time: TimeInterval) -> CIImage {
        let elapsed = time - startTime
        let zoom = 1.06 + 0.05 * sin(elapsed * 0.35)
        let driftX = 18 * sin(elapsed * 0.5)
        let driftY = 12 * cos(elapsed * 0.4)
        let fill = SpellRenderer.aspectFillTransform(imageExtent: portrait.extent, targetSize: outputSize)
        let center = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        let motion = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -center.x + driftX, y: -center.y + driftY)
        return portrait.transformed(by: fill.concatenating(motion)).cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    private func emitFrame() {
        guard let pool else { return }
        var bufferRef: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferRef)
        guard let buffer = bufferRef else { return }
        let now = CACurrentMediaTime()
        context.render(currentImage(at: now), to: buffer, bounds: CGRect(origin: .zero, size: outputSize), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        onFrame?(VideoFrame(pixelBuffer: buffer, timestamp: now, isMirrored: false))
    }
}
