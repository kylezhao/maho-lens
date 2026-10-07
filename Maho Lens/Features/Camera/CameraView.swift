//
//  CameraView.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

struct CameraView: View {
    @State private var viewModel: CameraViewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingGallery = false
    @State private var showingSettings = false
    /// Snapshot of the metrics taken as Settings opens, so the report reflects the viewfinder and
    /// not the occluded preview behind the sheet.
    @State private var frozenReport = ""

    init(settings: AppSettings) {
        _viewModel = State(initialValue: CameraViewModel(settings: settings))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalPreviewView(renderer: viewModel.previewRenderer, preferredFramesPerSecond: settings.frameRate.rawValue)
                .ignoresSafeArea()
                .accessibilityIdentifier("preview")
            FaceReticle(faceRect: viewModel.faceRect, frameSize: viewModel.frameSize)
                .ignoresSafeArea()
            Color.white
                .opacity(viewModel.flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            SparkleBurst(trigger: viewModel.sparkleTrigger)
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }
                bottomControls
            }
        }
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await viewModel.start() }
            case .background: viewModel.stop()
            default: break
            }
        }
        .sheet(isPresented: $showingGallery) {
            NavigationStack { GalleryView() }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            viewModel.setSegmentationQuality(settings.segmentationQuality)
            Task { await viewModel.setFrameRate(settings.frameRate) }
        }) {
            NavigationStack { SettingsView(report: frozenReport) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            fpsDial
            Spacer()
            if viewModel.isDemo {
                Badge(text: String(localized: "Demo"), systemImage: "photo.fill", tint: MahoTheme.lavender)
            }
            Button {
                Task { await viewModel.flipCamera() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityIdentifier("flipButton")
            .disabled(viewModel.isDemo)
            Button {
                frozenReport = viewModel.performanceReport
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Live frame-rate readout with the 30/60 target toggle. Green when the preview meets the target.
    private var fpsDial: some View {
        let metrics = viewModel.metrics
        let good = metrics.meetsTarget
        return Button {
            Task { await viewModel.toggleFrameRate() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(metrics.previewFPS == 0 ? Color.secondary : (good ? Color.green : MahoTheme.ember))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.0f", metrics.previewFPS))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("fpsLabel")
                        Text("fps").font(.caption2).foregroundStyle(.secondary)
                    }
                    if settings.showMetrics {
                        Text(String(format: "target %d · %.1fms · seg %.0fms", metrics.target.rawValue, metrics.renderMilliseconds, metrics.analysisMilliseconds))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    } else {
                        Text("target \(metrics.target.rawValue)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(MahoTheme.gold)
            }
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("fpsToggle")
        .animation(.snappy, value: metrics.previewFPS)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Spell.allCases) { spell in
                    SpellChip(spell: spell, isActive: spell.isActive(in: viewModel.spells)) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.toggle(spell) }
                    }
                }
            }
            .padding(.horizontal, 16)
            if let spell = viewModel.intensitySpell {
                HStack(spacing: 10) {
                    Image(systemName: spell.symbol).foregroundStyle(spell.tint)
                    Slider(value: Bindable(viewModel).intensity, in: 0...1)
                        .tint(spell.tint)
                        .accessibilityIdentifier("intensitySlider")
                    Text(String(format: "%.0f%%", viewModel.intensity * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack {
                galleryButton
                Spacer()
                shutterButton
                Spacer()
                Text(viewModel.spells.summary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.intensitySpell)
    }

    private var galleryButton: some View {
        Button {
            showingGallery = true
        } label: {
            Group {
                if let thumbnail = viewModel.lastThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(MahoTheme.lavender)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MahoTheme.gold.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("galleryButton")
    }

    private var shutterButton: some View {
        Button {
            Task { await viewModel.capture() }
        } label: {
            ZStack {
                Circle()
                    .stroke(MahoTheme.gold.opacity(0.8), lineWidth: 3)
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(MahoTheme.ribbon)
                    .frame(width: 72, height: 72)
                    .shadow(color: MahoTheme.pink.opacity(0.7), radius: 16)
                Image(systemName: viewModel.isCapturing ? "sparkles" : "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isCapturing || !viewModel.isRunning)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("shutterButton")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
            Spacer()
            Button { viewModel.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(MahoTheme.ember)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityIdentifier("errorLabel")
    }
}

/// A spell as a glass chip: title and incantation, glowing when active.
struct SpellChip: View {
    let spell: Spell
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: spell.symbol)
                    .font(.subheadline)
                    .symbolEffect(.bounce, value: isActive)
                VStack(alignment: .leading, spacing: 0) {
                    Text(spell.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(spell.incantation).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? spell.tint : .primary)
        .glassEffect(.regular.tint(isActive ? spell.tint.opacity(0.32) : .clear).interactive(), in: .capsule)
        .overlay {
            if isActive {
                Capsule().strokeBorder(spell.tint.opacity(0.7), lineWidth: 1)
            }
        }
        .accessibilityIdentifier("spell-\(spell.rawValue)")
    }
}

/// Glowing frame around the detected face, the Focus Charm's visible effect.
struct FaceReticle: View {
    let faceRect: CGRect?
    let frameSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            if let faceRect, frameSize != .zero {
                let rect = CameraGeometry.viewRect(for: faceRect, frameSize: frameSize, viewSize: proxy.size).insetBy(dx: -12, dy: -16)
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            AngularGradient(colors: [MahoTheme.pink, MahoTheme.gold, MahoTheme.lavender, MahoTheme.pink], center: .center),
                            lineWidth: 2.5
                        )
                        .shadow(color: MahoTheme.pink.opacity(0.6), radius: 8)
                    ForEach(0..<4, id: \.self) { corner in
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MahoTheme.gold)
                            .offset(
                                x: (corner % 2 == 0 ? -rect.width / 2 : rect.width / 2),
                                y: (corner < 2 ? -rect.height / 2 : rect.height / 2)
                            )
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeOut(duration: 0.18), value: rect)
                .accessibilityIdentifier("faceReticle")
            }
        }
        .allowsHitTesting(false)
    }
}
