//
//  MetalPreviewView.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreImage
import MetalKit
import os
import QuartzCore
import SwiftUI

/// Holds the newest frame, mask and spells, and renders them into an `MTKView` on every display tick.
/// Rendering only when a new frame arrived makes the measured preview rate the real one.
final class PreviewRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var pendingFrame: VideoFrame?
    private var mask: CIImage?
    private var spells = SpellState()
    private var hasNewFrame = false
    private(set) var frameSize = CGSize.zero

    let spellRenderer: SpellRenderer
    let monitor: PerformanceMonitor
    private let commandQueue: MTLCommandQueue?

    init(spellRenderer: SpellRenderer = SpellRenderer(), monitor: PerformanceMonitor) {
        self.spellRenderer = spellRenderer
        self.monitor = monitor
        self.commandQueue = spellRenderer.device?.makeCommandQueue()
        super.init()
    }

    func enqueue(_ frame: VideoFrame) {
        lock.withLock {
            pendingFrame = frame
            hasNewFrame = true
            frameSize = frame.size
        }
        monitor.recordCapture(at: frame.timestamp)
    }

    func update(mask: CIImage?) {
        lock.withLock { self.mask = mask }
    }

    func update(spells: SpellState) {
        lock.withLock { self.spells = spells }
    }

    func snapshotSpells() -> SpellState {
        lock.withLock { spells }
    }

    /// Renders the newest frame with the current spells, for stills captured from the demo source
    /// or for tests. Not used on the live path.
    func currentComposite() -> CIImage? {
        let (frame, mask, spells) = lock.withLock { (pendingFrame, self.mask, self.spells) }
        guard let frame else { return nil }
        return spellRenderer.apply(.init(image: CIImage(cvPixelBuffer: frame.pixelBuffer), mask: mask, spells: spells))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let (frame, mask, spells, isNew) = lock.withLock { () -> (VideoFrame?, CIImage?, SpellState, Bool) in
            let result = (pendingFrame, self.mask, self.spells, hasNewFrame)
            hasNewFrame = false
            return result
        }
        guard isNew, let frame, let commandQueue,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let start = CACurrentMediaTime()
        let image = spellRenderer.apply(.init(image: CIImage(cvPixelBuffer: frame.pixelBuffer), mask: mask, spells: spells))
        spellRenderer.render(image, to: drawable.texture, commandBuffer: commandBuffer, size: view.drawableSize)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        let milliseconds = (CACurrentMediaTime() - start) * 1000
        monitor.recordPreview(at: CACurrentMediaTime(), milliseconds: milliseconds)
    }
}

/// SwiftUI wrapper around an `MTKView` driven by `PreviewRenderer`.
struct MetalPreviewView: UIViewRepresentable {
    let renderer: PreviewRenderer
    let preferredFramesPerSecond: Int

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.spellRenderer.device)
        view.delegate = renderer
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.contentMode = .scaleAspectFill
        // The preview never handles touches itself; SwiftUI controls layered above it do.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if view.preferredFramesPerSecond != preferredFramesPerSecond {
            view.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }
}
