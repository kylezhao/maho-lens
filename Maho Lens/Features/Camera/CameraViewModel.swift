//
//  CameraViewModel.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreImage
import Foundation
import Observation
import QuartzCore
import SwiftUI
import UIKit

/// Wires the frame source, the Vision analyzer and the Metal preview together, and handles capture.
@MainActor
@Observable
final class CameraViewModel {
    let settings: AppSettings
    let monitor = PerformanceMonitor()
    let previewRenderer: PreviewRenderer
    private let analyzer: SubjectAnalyzer
    private let photoStore: PhotoStore
    private var source: (any FrameSource)?
    private var metricsTask: Task<Void, Never>?
    private var lastFocusPoint: CGPoint?
    private var lastFocusTime: TimeInterval = 0

    var spells = SpellState() {
        didSet {
            previewRenderer.update(spells: spells)
            if !spells.hasBlur { previewRenderer.update(mask: nil) }
        }
    }
    /// The spell whose strength the slider edits.
    var intensitySpell: Spell?
    private(set) var metrics: PerformanceSnapshot
    private(set) var faceRect: CGRect?
    private(set) var frameSize: CGSize = .zero
    private(set) var isRunning = false
    private(set) var isDemo = false
    private(set) var isCapturing = false
    private(set) var lastCapture: SavedPhoto?
    private(set) var lastThumbnail: UIImage?
    var flashOpacity: Double = 0
    var sparkleTrigger = 0
    var errorMessage: String?

    init(settings: AppSettings, photoStore: PhotoStore = .shared) {
        self.settings = settings
        self.photoStore = photoStore
        self.previewRenderer = PreviewRenderer(monitor: monitor)
        self.analyzer = SubjectAnalyzer(quality: settings.segmentationQuality)
        self.metrics = .idle(target: settings.frameRate)
        lastCapture = photoStore.all().first
        if let url = lastCapture?.url { lastThumbnail = Self.thumbnail(at: url) }
    }

    // MARK: - Lifecycle

    func start() async {
        if let source {
            source.start()
            isRunning = true
            startMetricsLoop()
            return
        }
        let useDemo = settings.forcesDemoSource || !CameraFrameSource.isAvailable
        let newSource: any FrameSource
        if useDemo {
            guard let demo = DemoFrameSource.bundled() else {
                errorMessage = String(localized: "The demo portrait is missing from the app bundle.")
                return
            }
            newSource = demo
        } else {
            newSource = CameraFrameSource()
        }
        isDemo = useDemo
        do {
            try await newSource.configure(CaptureConfiguration(position: settings.cameraPosition, frameRate: settings.frameRate))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        newSource.onFrame = { [weak self] frame in self?.handle(frame) }
        source = newSource
        previewRenderer.update(spells: spells)
        newSource.start()
        isRunning = true
        monitor.reset()
        startMetricsLoop()
    }

    func stop() {
        source?.stop()
        isRunning = false
        metricsTask?.cancel()
        metricsTask = nil
    }

    /// Runs on the source's queue. Only touches lock-protected or Sendable members.
    nonisolated private func handle(_ frame: VideoFrame) {
        previewRenderer.enqueue(frame)
        let spells = previewRenderer.currentSpells
        guard spells.hasBlur || spells.isFaceFocusEnabled else { return }
        analyzer.analyzeIfIdle(frame.pixelBuffer, wantsMask: spells.hasBlur, wantsFace: spells.isFaceFocusEnabled) { [weak self] info in
            guard let self else { return }
            monitor.recordAnalysis(at: info.timestamp, milliseconds: info.milliseconds)
            if spells.hasBlur { previewRenderer.update(mask: info.mask) }
            if spells.isFaceFocusEnabled {
                Task { @MainActor in self.updateFace(info.faceRect) }
            }
        }
    }

    private func updateFace(_ rect: CGRect?) {
        faceRect = rect
        guard let rect, spells.isFaceFocusEnabled, let source else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let now = CACurrentMediaTime()
        let moved = lastFocusPoint.map { hypot($0.x - center.x, $0.y - center.y) > 0.04 } ?? true
        if moved, now - lastFocusTime > 0.6 {
            source.focus(at: center)
            lastFocusPoint = center
            lastFocusTime = now
        }
    }

    private func startMetricsLoop() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                metrics = monitor.snapshot(target: settings.frameRate, source: source?.descriptor ?? "")
                frameSize = previewRenderer.frameSize
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: - Spells

    func toggle(_ spell: Spell) {
        spell.toggle(in: &spells)
        if spell.usesIntensity {
            intensitySpell = spell.isActive(in: spells) ? spell : nil
        } else if let current = intensitySpell, !current.isActive(in: spells) {
            intensitySpell = nil
        }
        if !spells.isFaceFocusEnabled { faceRect = nil }
        sparkleTrigger += 1
    }

    var intensity: Double {
        get { intensitySpell?.intensity(in: spells) ?? 0 }
        set {
            guard let intensitySpell else { return }
            intensitySpell.setIntensity(newValue, in: &spells)
        }
    }

    // MARK: - Camera controls

    func setFrameRate(_ frameRate: FrameRateSetting) async {
        settings.frameRate = frameRate
        monitor.reset()
        do {
            try await source?.setFrameRate(frameRate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFrameRate() async {
        await setFrameRate(settings.frameRate == .fps30 ? .fps60 : .fps30)
    }

    func flipCamera() async {
        settings.cameraPosition.flip()
        stop()
        source = nil
        faceRect = nil
        await start()
    }

    func setSegmentationQuality(_ quality: SegmentationQuality) {
        settings.segmentationQuality = quality
        analyzer.setQuality(quality)
    }

    // MARK: - Capture

    func capture() async {
        guard let source, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        sparkleTrigger += 1
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.9 }
        do {
            let photo = try await source.capturePhoto()
            withAnimation(.easeIn(duration: 0.35)) { flashOpacity = 0 }
            var mask: CIImage?
            if spells.hasBlur {
                let stillAnalyzer = SubjectAnalyzer(quality: .accurate)
                mask = await stillAnalyzer.analyze(photo.image, wantsMask: true, wantsFace: false).mask
            }
            let composite = previewRenderer.spellRenderer.apply(.init(image: photo.image, mask: mask, spells: spells))
            guard let jpeg = previewRenderer.spellRenderer.jpegData(from: composite) else {
                throw CameraError.captureFailed("Encoding failed.")
            }
            let saved = try photoStore.save(jpeg: jpeg, spells: spells)
            lastCapture = saved
            lastThumbnail = UIImage(data: jpeg)?.preparingThumbnail(of: CGSize(width: 180, height: 320))
            if settings.saveToPhotoLibrary {
                do {
                    try await PhotoStore.addToPhotoLibrary(jpeg: jpeg)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            withAnimation { flashOpacity = 0 }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reporting

    /// Text summary of the current performance for the submission metrics.
    var performanceReport: String {
        let range = monitor.previewRange
        return """
        Source: \(metrics.sourceDescription)
        Target: \(metrics.target.title) (minimum \(Int(metrics.target.minimumAcceptable)) fps)
        Preview: \(String(format: "%.1f", metrics.previewFPS)) fps (low \(String(format: "%.1f", range.low)), peak \(String(format: "%.1f", range.peak)))
        Capture: \(String(format: "%.1f", metrics.captureFPS)) fps
        Analysis: \(String(format: "%.1f", metrics.analysisFPS)) fps, \(String(format: "%.1f", metrics.analysisMilliseconds)) ms
        Render: \(String(format: "%.2f", metrics.renderMilliseconds)) ms per frame
        Spells: \(spells.summary)
        Result: \(metrics.meetsTarget ? "meets target" : "below target")
        """
    }

    static func thumbnail(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 180, height: 320))
    }
}

extension PreviewRenderer {
    /// The spells the renderer is currently using. Safe to read from any queue.
    var currentSpells: SpellState { snapshotSpells() }
}
