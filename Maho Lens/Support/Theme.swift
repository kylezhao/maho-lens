//
//  Theme.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

/// Magical-girl palette: candy pink, lavender, gold sparkles.
enum MahoTheme {
    static let pink = Color(red: 1.0, green: 0.42, blue: 0.68)
    static let lavender = Color(red: 0.72, green: 0.56, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.45)
    static let sky = Color(red: 0.56, green: 0.86, blue: 1.0)
    static let ember = Color(red: 1.0, green: 0.62, blue: 0.36)
    static let moon = Color(red: 0.88, green: 0.90, blue: 0.98)
    static let night = Color(red: 0.10, green: 0.05, blue: 0.20)

    static let ribbon = LinearGradient(colors: [pink, lavender], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let titleGradient = LinearGradient(colors: [gold, .white, pink], startPoint: .leading, endPoint: .trailing)

    static func heading(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }
}

/// Glass pill badge.
struct Badge: View {
    var text: String
    var systemImage: String
    var tint: Color = MahoTheme.gold

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
    }
}

/// Sparkle burst shown when a spell is cast or a photo is taken.
struct SparkleBurst: View {
    var trigger: Int
    /// Starts in the finished state so nothing shows until the first trigger.
    @State private var animate = true

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                let angle = Double(index) / 10 * 2 * .pi
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                    .font(.system(size: index.isMultiple(of: 3) ? 22 : 14))
                    .foregroundStyle(index.isMultiple(of: 2) ? MahoTheme.gold : MahoTheme.pink)
                    .offset(x: animate ? cos(angle) * 120 : 0, y: animate ? sin(angle) * 120 : 0)
                    .opacity(animate ? 0 : 1)
                    .scaleEffect(animate ? 0.4 : 1.2)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            animate = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.7)) { animate = true }
            }
        }
    }
}
