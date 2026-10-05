//
//  PhotoStore.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Photos
import UIKit

/// A photo kept in the app's own storage, with the spells that were active.
struct SavedPhoto: Identifiable, Hashable, Sendable {
    let url: URL
    let createdAt: Date
    let spells: SpellState?

    var id: URL { url }
}

/// Saves captures to Documents/Captures (always) and the Photos library (when allowed).
struct PhotoStore: Sendable {
    let directory: URL

    static let shared = PhotoStore(
        directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Captures", isDirectory: true)
    )

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func save(jpeg: Data, spells: SpellState, date: Date = .now) throws -> SavedPhoto {
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("MahoLens-\(stamp).jpg")
        try jpeg.write(to: url, options: .atomic)
        let sidecar = url.deletingPathExtension().appendingPathExtension("json")
        try JSONEncoder().encode(spells).write(to: sidecar, options: .atomic)
        return SavedPhoto(url: url, createdAt: date, spells: spells)
    }

    func all() -> [SavedPhoto] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let sidecar = url.deletingPathExtension().appendingPathExtension("json")
                let spells = (try? Data(contentsOf: sidecar)).flatMap { try? JSONDecoder().decode(SpellState.self, from: $0) }
                return SavedPhoto(url: url, createdAt: date, spells: spells)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ photo: SavedPhoto) {
        try? FileManager.default.removeItem(at: photo.url)
        try? FileManager.default.removeItem(at: photo.url.deletingPathExtension().appendingPathExtension("json"))
    }

    /// Adds the JPEG to the user's Photos library. Throws when add-only access is refused.
    static func addToPhotoLibrary(jpeg: Data) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw CameraError.photoLibraryDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
        }
    }
}
