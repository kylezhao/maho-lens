//
//  SpellTests.swift
//  Maho LensTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Maho_Lens

struct SpellStateTests {
    @Test func togglingSpellsEditsState() {
        var state = SpellState()
        Spell.frostVeil.toggle(in: &state)
        #expect(state.toneBalance == -Spell.defaultToneStrength)
        #expect(Spell.frostVeil.isActive(in: state))
        Spell.emberVeil.toggle(in: &state)
        #expect(state.toneBalance == Spell.defaultToneStrength)
        #expect(!Spell.frostVeil.isActive(in: state))
        Spell.emberVeil.toggle(in: &state)
        #expect(!state.hasTone)
        Spell.mistBarrier.toggle(in: &state)
        #expect(state.blurStrength == Spell.defaultBlurStrength)
        Spell.moonlightMono.toggle(in: &state)
        #expect(state.isGrayscale)
        #expect(state.summary == "Moonlight Mono · Mist Barrier")
    }

    @Test func intensityClampsAndKeepsDirection() {
        var state = SpellState()
        Spell.frostVeil.setIntensity(1.7, in: &state)
        #expect(state.toneBalance == -1)
        Spell.mistBarrier.setIntensity(-0.2, in: &state)
        #expect(state.blurStrength == 0)
        #expect(Spell.frostVeil.intensity(in: state) == 1)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var state = SpellState()
        Spell.emberVeil.toggle(in: &state)
        Spell.mistBarrier.setIntensity(0.3, in: &state)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SpellState.self, from: data) == state)
    }
}

struct SpellRendererTests {
    private let renderer = SpellRenderer(device: nil)

    private func gray(_ value: CGFloat = 0.5, size: CGSize = CGSize(width: 64, height: 64)) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value)).cropped(to: CGRect(origin: .zero, size: size))
    }

    @Test func warmToneRaisesRedAboveBlue() throws {
        let warm = renderer.tone(gray(), balance: 0.8)
        let color = try #require(renderer.averageColor(of: warm))
        #expect(color.red > color.blue + 0.05, "warm: \(color)")
    }

    @Test func coolToneRaisesBlueAboveRed() throws {
        let cool = renderer.tone(gray(), balance: -0.8)
        let color = try #require(renderer.averageColor(of: cool))
        #expect(color.blue > color.red + 0.05, "cool: \(color)")
    }

    @Test func grayscaleRemovesSaturation() throws {
        let pink = CIImage(color: CIColor(red: 1, green: 0.3, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let mono = renderer.grayscale(pink)
        let color = try #require(renderer.averageColor(of: mono))
        #expect(abs(color.red - color.green) < 0.03)
        #expect(abs(color.green - color.blue) < 0.03)
    }

    @Test func blurKeepsSubjectAndSoftensBackground() throws {
        // Left half white, right half black: a sharp edge. Mask protects the left half.
        let size = CGSize(width: 128, height: 64)
        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let black = CIImage(color: .black).cropped(to: CGRect(x: 64, y: 0, width: 64, height: 64))
        let image = white.composited(over: black).cropped(to: CGRect(origin: .zero, size: size))
        let maskWhite = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let maskBlack = CIImage(color: .black).cropped(to: CGRect(x: 16, y: 0, width: 16, height: 16))
        let mask = maskWhite.composited(over: maskBlack).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 16))

        let output = renderer.blurBackground(of: image, mask: mask, strength: 1)
        let subjectRegion = output.cropped(to: CGRect(x: 4, y: 8, width: 24, height: 48))
        let backgroundEdge = output.cropped(to: CGRect(x: 72, y: 8, width: 24, height: 48))
        let subject = try #require(renderer.averageColor(of: subjectRegion))
        let background = try #require(renderer.averageColor(of: backgroundEdge))
        #expect(subject.red > 0.95, "subject stays sharp white: \(subject)")
        #expect(background.red > 0.02, "background near the edge picks up blurred white: \(background)")
        #expect(output.extent == image.extent)
    }

    @Test func applyWithoutSpellsReturnsInput() {
        let image = gray()
        let output = renderer.apply(.init(image: image, mask: nil, spells: SpellState()))
        #expect(output.extent == image.extent)
    }

    @Test func aspectFillCoversTarget() {
        let transform = SpellRenderer.aspectFillTransform(imageExtent: CGRect(x: 0, y: 0, width: 1080, height: 1920), targetSize: CGSize(width: 390, height: 844))
        let fitted = CGRect(x: 0, y: 0, width: 1080, height: 1920).applying(transform)
        #expect(fitted.width >= 390 - 0.5)
        #expect(fitted.height >= 844 - 0.5)
        #expect(abs(fitted.midX - 195) < 0.5)
        #expect(abs(fitted.midY - 422) < 0.5)
    }
}

struct GeometryTests {
    @Test func portraitCornersMapToLandscapeSensorPoints() {
        #expect(CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 0, y: 0), mirrored: false) == CGPoint(x: 0, y: 1))
        #expect(CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 1, y: 0), mirrored: false) == CGPoint(x: 0, y: 0))
        #expect(CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 0, y: 1), mirrored: false) == CGPoint(x: 1, y: 1))
        #expect(CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 0.5, y: 0.5), mirrored: false) == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func mirroringFlipsHorizontalAxisFirst() {
        let mirrored = CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 0, y: 0), mirrored: true)
        #expect(mirrored == CameraGeometry.devicePoint(fromPortraitPoint: CGPoint(x: 1, y: 0), mirrored: false))
    }

    @Test func visionRectFlipsToTopLeftOrigin() {
        let rect = CameraGeometry.topLeftRect(fromVisionRect: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.3))
        #expect(abs(rect.minY - 0.1) < 1e-9)
        #expect(rect.minX == 0.1)
    }

    @Test func viewRectFollowsAspectFill() {
        let frame = CGSize(width: 1080, height: 1920)
        let view = CGSize(width: 390, height: 844)
        let centered = CameraGeometry.viewRect(for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), frameSize: frame, viewSize: view)
        #expect(abs(centered.midX - 195) < 0.5)
        #expect(abs(centered.midY - 422) < 0.5)
    }
}

struct FormatSelectionTests {
    struct Fake: FormatCandidate {
        let frameWidth: Int
        let frameHeight: Int
        let maximumFrameRate: Double
        let isBinned: Bool
    }

    private let formats = [
        Fake(frameWidth: 640, frameHeight: 480, maximumFrameRate: 60, isBinned: true),
        Fake(frameWidth: 1280, frameHeight: 720, maximumFrameRate: 60, isBinned: false),
        Fake(frameWidth: 1920, frameHeight: 1080, maximumFrameRate: 30, isBinned: false),
        Fake(frameWidth: 1920, frameHeight: 1080, maximumFrameRate: 60, isBinned: true),
        Fake(frameWidth: 3840, frameHeight: 2160, maximumFrameRate: 30, isBinned: false),
    ]

    @Test func picksTallestFormatThatSupportsTheRate() {
        let sixty = FormatSelector.select(from: formats, frameRate: 60)
        #expect(sixty?.frameHeight == 1080)
        #expect(sixty?.maximumFrameRate == 60)
        let thirty = FormatSelector.select(from: formats, frameRate: 30)
        #expect(thirty?.frameHeight == 1080)
        #expect(thirty?.isBinned == false, "unbinned wins the tie at 1080p")
    }

    @Test func fallsBackToClosestWhenNothingFitsTheCap() {
        let only4K = [Fake(frameWidth: 3840, frameHeight: 2160, maximumFrameRate: 60, isBinned: false)]
        #expect(FormatSelector.select(from: only4K, frameRate: 60)?.frameHeight == 2160)
        #expect(FormatSelector.select(from: only4K, frameRate: 120) == nil)
    }
}

struct PerformanceTests {
    @Test func frameRateCounterUsesOneSecondWindow() {
        var counter = FrameRateCounter()
        for index in 0..<120 { counter.record(at: Double(index) / 60) }
        #expect(abs(counter.fps(at: 2.0) - 60) <= 1)
        #expect(counter.fps(at: 10) == 0)
    }

    @Test func rollingAverageKeepsRecentSamples() {
        var average = RollingAverage(capacity: 3)
        for value in [10.0, 20.0, 30.0, 40.0] { average.add(value) }
        #expect(average.average == 30)
    }

    @Test func thresholdsMatchTheAssignment() {
        #expect(FrameRateSetting.fps30.minimumAcceptable == 25)
        #expect(FrameRateSetting.fps60.minimumAcceptable == 50)
        var snapshot = PerformanceSnapshot.idle(target: .fps60)
        snapshot.previewFPS = 49.9
        #expect(!snapshot.meetsTarget)
        snapshot.previewFPS = 50
        #expect(snapshot.meetsTarget)
    }

    @Test func monitorReportsPreviewRange() {
        let monitor = PerformanceMonitor()
        for index in 0..<30 { monitor.recordPreview(at: Double(index) / 30, milliseconds: 4) }
        let snapshot = monitor.snapshot(target: .fps30, source: "test", at: 1.0)
        #expect(abs(snapshot.previewFPS - 30) <= 1)
        #expect(snapshot.meetsTarget)
        #expect(snapshot.renderMilliseconds == 4)
        #expect(monitor.previewRange.peak >= 29)
    }
}

struct PhotoStoreTests {
    @Test func savesListsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MahoLensTests-\(UUID().uuidString)")
        let store = PhotoStore(directory: directory)
        var spells = SpellState()
        Spell.emberVeil.toggle(in: &spells)
        let renderer = SpellRenderer(device: nil)
        let image = CIImage(color: CIColor(red: 1, green: 0.5, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let jpeg = try #require(renderer.jpegData(from: image))
        let saved = try store.save(jpeg: jpeg, spells: spells)
        #expect(FileManager.default.fileExists(atPath: saved.url.path))
        let listed = store.all()
        #expect(listed.count == 1)
        #expect(listed.first?.spells == spells)
        store.delete(saved)
        #expect(store.all().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Vision on the bundled demo portrait. Exercises the same analyzer the live preview uses.
struct SubjectAnalyzerTests {
    @Test(.timeLimit(.minutes(2))) func findsFaceAndPersonInDemoPortrait() async throws {
        let url = try #require(Bundle.main.url(forResource: "demo-portrait", withExtension: "jpg"))
        let image = try #require(CIImage(contentsOf: url))
        let analyzer = SubjectAnalyzer(quality: .balanced)
        let info = await analyzer.analyze(image)
        let diagnostics = "lastError=\(analyzer.lastError ?? "none"), extent=\(image.extent), ms=\(info.milliseconds)"
        let face = try #require(info.faceRect, "No face found in demo portrait: \(diagnostics)")
        #expect(face.width > 0.1 && face.width < 0.9)
        #expect(face.minY >= 0 && face.maxY <= 1)
        #expect(info.milliseconds > 0)
        if let mask = info.mask {
            #expect(mask.extent.width > 0)
            let renderer = SpellRenderer(device: nil)
            let coverage = try #require(renderer.averageColor(of: mask))
            #expect(coverage.red > 0.15, "the person should cover a good part of the frame: \(coverage)")
            print("Mask kind: \(info.maskIsSynthetic ? "synthetic (segmentation unavailable: \(analyzer.lastError ?? "?"))" : "segmentation")")
        } else {
            #if targetEnvironment(simulator)
            print("Person segmentation unavailable in the Simulator: \(analyzer.lastError ?? "no error recorded")")
            #else
            Issue.record("Person segmentation returned no mask on device: \(analyzer.lastError ?? "no error")")
            #endif
        }
    }
}

/// Writes which Vision face-detection paths work in this environment to /tmp/maho-face-diag.txt,
/// so Simulator-only gaps can be told apart from real bugs. Always passes.
struct FaceDetectionDiagnostics {
    @Test(.timeLimit(.minutes(2))) func probeFaceDetectionPaths() async throws {
        let url = try #require(Bundle.main.url(forResource: "demo-portrait", withExtension: "jpg"))
        let ciImage = try #require(CIImage(contentsOf: url))
        let context = CIContext(options: nil)
        let cgImage = try #require(context.createCGImage(ciImage, from: ciImage.extent))
        var lines: [String] = []

        func run(_ label: String, _ handler: VNImageRequestHandler, revision: Int?) {
            let request = VNDetectFaceRectanglesRequest()
            if let revision { request.revision = revision }
            do {
                try handler.perform([request])
                lines.append("\(label) rev=\(request.revision): faces=\(request.results?.count ?? 0) \(request.results?.first.map { "\($0.boundingBox)" } ?? "")")
            } catch {
                lines.append("\(label) rev=\(request.revision): error=\(error.localizedDescription)")
            }
        }
        lines.append("supported revisions: \(VNDetectFaceRectanglesRequest.supportedRevisions.sorted())")
        run("ciImage", VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:]), revision: nil)
        run("cgImage", VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]), revision: nil)
        for revision in VNDetectFaceRectanglesRequest.supportedRevisions.sorted() {
            run("cgImage", VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]), revision: revision)
        }
        let landmarks = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]).perform([landmarks])
            lines.append("landmarks: faces=\(landmarks.results?.count ?? 0)")
        } catch {
            lines.append("landmarks: error=\(error.localizedDescription)")
        }
        let human = VNDetectHumanRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]).perform([human])
            lines.append("humanRectangles: count=\(human.results?.count ?? 0)")
        } catch {
            lines.append("humanRectangles: error=\(error.localizedDescription)")
        }
        try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/maho-face-diag.txt"), atomically: true, encoding: .utf8)
        #expect(!lines.isEmpty)
    }
}

import Vision
