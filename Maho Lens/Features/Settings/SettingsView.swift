//
//  SettingsView.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let report: String
    @State private var copied = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Preview frame rate", selection: $settings.frameRate) {
                    ForEach(FrameRateSetting.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("At 30 fps the preview must stay above 25 fps; at 60 fps above 50 fps. The dial on the camera screen turns green when it does.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Camera", selection: $settings.cameraPosition) {
                    ForEach(CameraPosition.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Capture")
            }

            Section {
                Picker("Person segmentation", selection: $settings.segmentationQuality) {
                    ForEach(SegmentationQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Fast gives a coarser mask but leaves more time for 60 fps. Stills always use Accurate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mist Barrier")
            }

            Section {
                Toggle("Show performance metrics", isOn: $settings.showMetrics)
                Toggle("Also save to Photos library", isOn: $settings.saveToPhotoLibrary)
            } header: {
                Text("Display and saving")
            }

            Section {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Performance report")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Copyright © 2026 Kyle Zhao. All rights reserved.").font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
