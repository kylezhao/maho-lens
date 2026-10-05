//
//  CameraFrameSource.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

@preconcurrency import AVFoundation
import CoreImage
import Foundation

extension AVCaptureDevice.Format: FormatCandidate {
    var frameHeight: Int { Int(CMVideoFormatDescriptionGetDimensions(formatDescription).height) }
    var frameWidth: Int { Int(CMVideoFormatDescriptionGetDimensions(formatDescription).width) }
    var maximumFrameRate: Double { videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0 }
    var isBinned: Bool { isVideoBinned }
}

/// Live camera through `AVCaptureSession`. Video frames arrive as BGRA, rotated upright for portrait
/// and mirrored for the front camera, so the rest of the pipeline never thinks about orientation.
final class CameraFrameSource: NSObject, FrameSource, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.kylezhao.MahoLens.session")
    private let videoQueue = DispatchQueue(label: "com.kylezhao.MahoLens.video", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var configuration = CaptureConfiguration(position: .front, frameRate: .fps30)
    private var photoContinuation: CheckedContinuation<CapturedPhoto, any Error>?

    var onFrame: ((VideoFrame) -> Void)?
    private(set) var descriptor = "Camera"
    var isMirrored: Bool { configuration.position == .front }

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    // MARK: - FrameSource

    func configure(_ configuration: CaptureConfiguration) async throws {
        try await Self.ensureAuthorization()
        self.configuration = configuration
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSession(configuration)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setFrameRate(_ frameRate: FrameRateSetting) async throws {
        configuration.frameRate = frameRate
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [self] in
                guard let device else { return continuation.resume(throwing: CameraError.noCamera) }
                do {
                    session.beginConfiguration()
                    try Self.applyFormat(to: device, frameRate: frameRate)
                    session.commitConfiguration()
                    descriptor = Self.describe(device: device, position: configuration.position)
                    continuation.resume()
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func focus(at point: CGPoint) {
        let devicePoint = CameraGeometry.devicePoint(fromPortraitPoint: point, mirrored: isMirrored)
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {}
        }
    }

    func capturePhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard photoContinuation == nil else {
                    return continuation.resume(throwing: CameraError.captureFailed("A capture is already in progress."))
                }
                photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                if let connection = photoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = isMirrored
                    }
                }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Configuration

    private static func ensureAuthorization() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.accessDenied }
        default:
            throw CameraError.accessDenied
        }
    }

    private func configureSession(_ configuration: CaptureConfiguration) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority

        if let input {
            session.removeInput(input)
            self.input = nil
        }
        let position: AVCaptureDevice.Position = configuration.position == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.configurationFailed("Input rejected.") }
        session.addInput(input)
        self.input = input
        self.device = device

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else { throw CameraError.configurationFailed("Video output rejected.") }
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw CameraError.configurationFailed("Photo output rejected.") }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        try Self.applyFormat(to: device, frameRate: configuration.frameRate)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = configuration.position == .front
            }
        }
        descriptor = Self.describe(device: device, position: configuration.position)
    }

    private static func applyFormat(to device: AVCaptureDevice, frameRate: FrameRateSetting) throws {
        guard let format = FormatSelector.select(from: device.formats, frameRate: frameRate.rawValue) else {
            throw CameraError.configurationFailed("No format supports \(frameRate.rawValue) fps.")
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
    }

    private static func describe(device: AVCaptureDevice, position: CameraPosition) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let fps = Int((1 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)).rounded())
        return "\(position.title) camera \(dimensions.width)×\(dimensions.height) @\(fps)"
    }
}

// MARK: - Video frames

extension CameraFrameSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        onFrame?(VideoFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, isMirrored: isMirrored))
    }
}

// MARK: - Stills

extension CameraFrameSource: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        sessionQueue.async { [self] in
            guard let continuation = photoContinuation else { return }
            photoContinuation = nil
            if let error {
                return continuation.resume(throwing: CameraError.captureFailed(error.localizedDescription))
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                return continuation.resume(throwing: CameraError.captureFailed("No image data."))
            }
            continuation.resume(returning: CapturedPhoto(image: image))
        }
    }
}
