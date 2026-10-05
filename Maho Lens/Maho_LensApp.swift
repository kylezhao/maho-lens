//
//  Maho_LensApp.swift
//  Maho Lens
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

@main
struct Maho_LensApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            CameraView(settings: settings)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(MahoTheme.pink)
        }
    }
}
