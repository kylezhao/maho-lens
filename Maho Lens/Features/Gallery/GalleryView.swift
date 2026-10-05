//
//  GalleryView.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

/// Photos kept in the app's own storage.
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [SavedPhoto] = []
    @State private var selected: SavedPhoto?
    private let store = PhotoStore.shared

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [MahoTheme.night, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundStyle(MahoTheme.titleGradient)
                    Text("No transformations yet")
                        .font(MahoTheme.heading(.title3))
                        .foregroundStyle(MahoTheme.titleGradient)
                    Text("Photos you take are kept here and, if allowed, in your Photos library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(photos) { photo in
                            Button { selected = photo } label: {
                                GalleryThumbnail(url: photo.url)
                                    .aspectRatio(9 / 16, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .bottomLeading) {
                                        if let spells = photo.spells, !spells.activeSpells.filter({ $0 != .focusCharm }).isEmpty {
                                            Text(spells.summary)
                                                .font(.system(size: 9, weight: .semibold))
                                                .lineLimit(2)
                                                .padding(5)
                                                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                                                .padding(6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                ShareLink(item: photo.url) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { delete(photo) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Transformations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear { photos = store.all() }
        .sheet(item: $selected) { photo in
            PhotoDetailView(photo: photo) {
                delete(photo)
                selected = nil
            }
        }
        .preferredColorScheme(.dark)
    }

    private func delete(_ photo: SavedPhoto) {
        store.delete(photo)
        photos = store.all()
    }
}

/// Downsampled thumbnail so the grid stays light.
struct GalleryThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .task(id: url) {
            let target = url
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: target.path)?.preparingThumbnail(of: CGSize(width: 300, height: 540))
            }.value
        }
    }
}

struct PhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: SavedPhoto
    let onDelete: () -> Void
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .task { image = UIImage(contentsOfFile: photo.url.path) }
            .navigationTitle(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: photo.url) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let spells = photo.spells {
                    Text(spells.summary)
                        .font(.footnote)
                        .padding(10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
