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
    /// Rendering targets the view's Metal layer directly from the capture queue: no display timer to
    /// beat against the camera rate, and no main-thread hop where frames could coalesce. The layer's
    /// drawable pool paces presentation to the display's refresh.
    private weak var metalLayer: CAMetalLayer?
    private var drawableSize = CGSize.zero

    init(spellRenderer: SpellRenderer = SpellRenderer(), monitor: PerformanceMonitor) {
        self.spellRenderer = spellRenderer
        self.monitor = monitor
        self.commandQueue = spellRenderer.device?.makeCommandQueue()
        super.init()
    }

    @MainActor
    func attach(_ view: MTKView) {
        let layer = view.layer as? CAMetalLayer
        lock.withLock {
            metalLayer = layer
            drawableSize = view.drawableSize
        }
    }

    /// Called on the source's queue for every frame. Renders immediately.
    func enqueue(_ frame: VideoFrame) {
        let (layer, size, mask, spells) = lock.withLock { () -> (CAMetalLayer?, CGSize, CIImage?, SpellState) in
            pendingFrame = frame
            hasNewFrame = true
            frameSize = frame.size
            return (metalLayer, drawableSize, self.mask, self.spells)
        }
        monitor.recordCapture(at: frame.timestamp)
        guard let layer, size != .zero, let commandQueue else { return }
        // Blocks when all drawables are in flight, which paces us to the display without dropping
        // more than the camera already discards for late frames.
        guard let drawable = layer.nextDrawable(), let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let start = CACurrentMediaTime()
        let image = spellRenderer.apply(.init(image: CIImage(cvPixelBuffer: frame.pixelBuffer), mask: mask, spells: spells))
        spellRenderer.render(image, to: drawable.texture, commandBuffer: commandBuffer, size: size)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        lock.withLock { hasNewFrame = false }
        monitor.recordPreview(at: CACurrentMediaTime(), milliseconds: (CACurrentMediaTime() - start) * 1000)
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lock.withLock { drawableSize = size }
    }

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
        // Paused: `PreviewRenderer.enqueue` renders into the layer for every captured frame instead.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.autoResizeDrawable = true
        renderer.attach(view)
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
        renderer.attach(view)
    }
}
