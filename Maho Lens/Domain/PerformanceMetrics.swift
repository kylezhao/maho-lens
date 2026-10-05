//
//  PerformanceMetrics.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import os

/// Frames per second over a sliding one-second window.
struct FrameRateCounter: Sendable {
    private var timestamps: [TimeInterval] = []
    let window: TimeInterval

    init(window: TimeInterval = 1.0) {
        self.window = window
    }

    mutating func record(at time: TimeInterval) {
        timestamps.append(time)
        prune(before: time - window)
    }

    mutating func prune(before cutoff: TimeInterval) {
        if let index = timestamps.firstIndex(where: { $0 >= cutoff }) {
            if index > 0 { timestamps.removeFirst(index) }
        } else {
            timestamps.removeAll()
        }
    }

    /// Frames recorded in the last window, scaled to one second.
    func fps(at time: TimeInterval) -> Double {
        let cutoff = time - window
        let count = timestamps.reduce(0) { $0 + ($1 >= cutoff ? 1 : 0) }
        return Double(count) / window
    }

    mutating func reset() { timestamps.removeAll() }
}

/// Mean of the most recent samples.
struct RollingAverage: Sendable {
    private var samples: [Double] = []
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    mutating func add(_ value: Double) {
        samples.append(value)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    var average: Double {
        samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
    }

    mutating func reset() { samples.removeAll() }
}

/// What the HUD shows and what the performance report records.
struct PerformanceSnapshot: Equatable, Sendable {
    var target: FrameRateSetting
    var captureFPS: Double
    var previewFPS: Double
    var analysisFPS: Double
    var renderMilliseconds: Double
    var analysisMilliseconds: Double
    var sourceDescription: String

    var meetsTarget: Bool { previewFPS >= target.minimumAcceptable }

    static func idle(target: FrameRateSetting) -> PerformanceSnapshot {
        PerformanceSnapshot(target: target, captureFPS: 0, previewFPS: 0, analysisFPS: 0, renderMilliseconds: 0, analysisMilliseconds: 0, sourceDescription: "")
    }
}

/// Thread-safe collector fed from the capture, analysis and render queues.
final class PerformanceMonitor: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var capture = FrameRateCounter()
    private var preview = FrameRateCounter()
    private var analysis = FrameRateCounter()
    private var renderTime = RollingAverage()
    private var analysisTime = RollingAverage()
    private var peakPreviewFPS: Double = 0
    private var lowPreviewFPS: Double = .infinity

    func recordCapture(at time: TimeInterval = CACurrentMediaTime()) {
        lock.withLock { capture.record(at: time) }
    }

    func recordPreview(at time: TimeInterval = CACurrentMediaTime(), milliseconds: Double) {
        lock.withLock {
            preview.record(at: time)
            renderTime.add(milliseconds)
        }
    }

    func recordAnalysis(at time: TimeInterval = CACurrentMediaTime(), milliseconds: Double) {
        lock.withLock {
            analysis.record(at: time)
            analysisTime.add(milliseconds)
        }
    }

    func snapshot(target: FrameRateSetting, source: String, at time: TimeInterval = CACurrentMediaTime()) -> PerformanceSnapshot {
        lock.withLock {
            let previewFPS = preview.fps(at: time)
            if previewFPS > 0 {
                peakPreviewFPS = max(peakPreviewFPS, previewFPS)
                lowPreviewFPS = min(lowPreviewFPS, previewFPS)
            }
            return PerformanceSnapshot(
                target: target,
                captureFPS: capture.fps(at: time),
                previewFPS: previewFPS,
                analysisFPS: analysis.fps(at: time),
                renderMilliseconds: renderTime.average,
                analysisMilliseconds: analysisTime.average,
                sourceDescription: source
            )
        }
    }

    /// Peak and low preview rates since the last reset, for the performance report.
    var previewRange: (low: Double, peak: Double) {
        lock.withLock { (lowPreviewFPS == .infinity ? 0 : lowPreviewFPS, peakPreviewFPS) }
    }

    func reset() {
        lock.withLock {
            capture.reset(); preview.reset(); analysis.reset()
            renderTime.reset(); analysisTime.reset()
            peakPreviewFPS = 0; lowPreviewFPS = .infinity
        }
    }
}

import QuartzCore
