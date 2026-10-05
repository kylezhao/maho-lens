//
//  Spell.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftUI

/// The live filter state. Every property is a spell the magical girl can cast on the preview.
struct SpellState: Hashable, Codable, Sendable {
    /// -1 is fully cool (Frost Veil), +1 is fully warm (Ember Veil), 0 is off.
    var toneBalance: Double = 0
    var isGrayscale = false
    /// 0 is no blur, 1 is the strongest Mist Barrier.
    var blurStrength: Double = 0
    var isFaceFocusEnabled = true

    var hasTone: Bool { abs(toneBalance) > 0.01 }
    var hasBlur: Bool { blurStrength > 0.01 }

    var activeSpells: [Spell] { Spell.allCases.filter { $0.isActive(in: self) } }

    var summary: String {
        let names = activeSpells.filter { $0 != .focusCharm }.map(\.title)
        return names.isEmpty ? String(localized: "No spells") : names.joined(separator: " · ")
    }
}

/// A cosmetic spell. Toggling one edits `SpellState`; intensity spells also expose a 0...1 strength.
enum Spell: String, CaseIterable, Identifiable, Codable, Sendable {
    case frostVeil
    case emberVeil
    case moonlightMono
    case mistBarrier
    case focusCharm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frostVeil: String(localized: "Frost Veil")
        case .emberVeil: String(localized: "Ember Veil")
        case .moonlightMono: String(localized: "Moonlight Mono")
        case .mistBarrier: String(localized: "Mist Barrier")
        case .focusCharm: String(localized: "Focus Charm")
        }
    }

    /// Short incantation shown under the title.
    var incantation: String {
        switch self {
        case .frostVeil: String(localized: "Cool tones")
        case .emberVeil: String(localized: "Warm tones")
        case .moonlightMono: String(localized: "Grayscale")
        case .mistBarrier: String(localized: "Background blur")
        case .focusCharm: String(localized: "Face focus")
        }
    }

    var symbol: String {
        switch self {
        case .frostVeil: "snowflake"
        case .emberVeil: "flame.fill"
        case .moonlightMono: "moon.stars.fill"
        case .mistBarrier: "cloud.fog.fill"
        case .focusCharm: "scope"
        }
    }

    var tint: Color {
        switch self {
        case .frostVeil: MahoTheme.sky
        case .emberVeil: MahoTheme.ember
        case .moonlightMono: MahoTheme.moon
        case .mistBarrier: MahoTheme.lavender
        case .focusCharm: MahoTheme.gold
        }
    }

    /// Spells whose strength the slider controls.
    var usesIntensity: Bool {
        switch self {
        case .frostVeil, .emberVeil, .mistBarrier: true
        case .moonlightMono, .focusCharm: false
        }
    }

    static let defaultToneStrength = 0.6
    static let defaultBlurStrength = 0.6

    func isActive(in state: SpellState) -> Bool {
        switch self {
        case .frostVeil: state.toneBalance < -0.01
        case .emberVeil: state.toneBalance > 0.01
        case .moonlightMono: state.isGrayscale
        case .mistBarrier: state.hasBlur
        case .focusCharm: state.isFaceFocusEnabled
        }
    }

    func toggle(in state: inout SpellState) {
        switch self {
        case .frostVeil:
            state.toneBalance = isActive(in: state) ? 0 : -Self.defaultToneStrength
        case .emberVeil:
            state.toneBalance = isActive(in: state) ? 0 : Self.defaultToneStrength
        case .moonlightMono:
            state.isGrayscale.toggle()
        case .mistBarrier:
            state.blurStrength = isActive(in: state) ? 0 : Self.defaultBlurStrength
        case .focusCharm:
            state.isFaceFocusEnabled.toggle()
        }
    }

    func intensity(in state: SpellState) -> Double {
        switch self {
        case .frostVeil, .emberVeil: abs(state.toneBalance)
        case .mistBarrier: state.blurStrength
        case .moonlightMono, .focusCharm: isActive(in: state) ? 1 : 0
        }
    }

    func setIntensity(_ value: Double, in state: inout SpellState) {
        let clamped = min(1, max(0, value))
        switch self {
        case .frostVeil: state.toneBalance = -clamped
        case .emberVeil: state.toneBalance = clamped
        case .mistBarrier: state.blurStrength = clamped
        case .moonlightMono: state.isGrayscale = clamped > 0.5
        case .focusCharm: state.isFaceFocusEnabled = clamped > 0.5
        }
    }
}
