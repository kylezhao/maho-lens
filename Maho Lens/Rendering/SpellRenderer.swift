//
//  SpellRenderer.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal

/// Builds the Core Image graph for a frame: background blur behind the subject mask, then toning,
/// then grayscale. The graph is lazy; the GPU work happens when the image is rendered.
final class SpellRenderer: @unchecked Sendable {
    let device: MTLDevice?
    let context: CIContext
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The blur runs on a downscaled copy; this is the scale factor. Smaller is faster and softer.
    static let blurDownscale: CGFloat = 0.25

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
        if let device {
            context = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .name: "MahoLens",
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            ])
        } else {
            context = CIContext(options: [.name: "MahoLens"])
        }
    }

    struct Input {
        var image: CIImage
        /// Person mask in the image's orientation; white where the subject is. Any resolution.
        var mask: CIImage?
        var spells: SpellState
    }

    func apply(_ input: Input) -> CIImage {
        var image = input.image
        if input.spells.hasBlur, let mask = input.mask {
            image = blurBackground(of: image, mask: mask, strength: input.spells.blurStrength)
        }
        if input.spells.hasTone {
            image = tone(image, balance: input.spells.toneBalance)
        }
        if input.spells.isGrayscale {
            image = grayscale(image)
        }
        return image
    }

    // MARK: - Spells

    /// Blurs everything outside the mask. Blur runs at quarter resolution, which keeps 60 fps within
    /// reach on recent iPhones and gives a soft, lens-like fall-off once scaled back up.
    func blurBackground(of image: CIImage, mask: CIImage, strength: Double) -> CIImage {
        let extent = image.extent
        let scale = Self.blurDownscale
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sigma = 1.5 + strength * 10
        let blurredSmall = small.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: small.extent)
        let blurred = blurredSmall
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .cropped(to: extent)

        let maskSoft = mask.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: mask.extent)
        let maskScaled = maskSoft.transformed(by: CGAffineTransform(
            scaleX: extent.width / mask.extent.width,
            y: extent.height / mask.extent.height
        )).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = blurred
        blend.maskImage = maskScaled
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Shifts white balance. Positive balance pushes toward warm (amber), negative toward cool (blue).
    /// `CITemperatureAndTint` warms the picture when the target neutral is *below* the source neutral,
    /// so the balance is subtracted.
    func tone(_ image: CIImage, balance: Double) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        filter.targetNeutral = CIVector(x: 6500 - CGFloat(balance) * 3500, y: 0)
        return filter.outputImage ?? image
    }

    func grayscale(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = 0
        return filter.outputImage ?? image
    }

    // MARK: - Output

    /// Aspect-fill transform placing `imageExtent` inside `targetSize`.
    static func aspectFillTransform(imageExtent: CGRect, targetSize: CGSize) -> CGAffineTransform {
        let scale = max(targetSize.width / imageExtent.width, targetSize.height / imageExtent.height)
        let scaledSize = CGSize(width: imageExtent.width * scale, height: imageExtent.height * scale)
        let offset = CGPoint(x: (targetSize.width - scaledSize.width) / 2, y: (targetSize.height - scaledSize.height) / 2)
        return CGAffineTransform(translationX: -imageExtent.minX, y: -imageExtent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
    }

    func render(_ image: CIImage, to texture: MTLTexture, commandBuffer: MTLCommandBuffer, size: CGSize) {
        let fitted = image.transformed(by: Self.aspectFillTransform(imageExtent: image.extent, targetSize: size))
        context.render(fitted, to: texture, commandBuffer: commandBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
    }

    func jpegData(from image: CIImage, quality: CGFloat = 0.92) -> Data? {
        context.jpegRepresentation(of: image, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    func cgImage(from image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    /// Average color of an image, used by tests to verify spell directions.
    func averageColor(of image: CIImage) -> (red: Double, green: Double, blue: Double)? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}

import ImageIO
