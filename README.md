# Maho Lens（魔法レンズ）

> A *mahō shōjo* beauty camera for iOS. Every filter is a transformation spell.

Maho Lens plays on the magical-girl trope of instant transformation: pick a
spell and the live camera preview changes on the spot.

Built for the Metanomaly iOS programming assignment (Beauty Camera).

## Status

Skeleton only. This is the stock Xcode SwiftUI + SwiftData template with
naming and file headers set up. Feature work has not started yet.

## Planned features

- Single-person face detection and focus
- Cool and warm color toning
- Grayscale for the entire preview
- Background blur outside the subject, with adjustable blur strength
- Take photos and save them to local storage

Preview performance targets:

| FPS setting | Minimum actual preview FPS |
| ----------- | -------------------------- |
| 30          | 25                         |
| 60          | 50                         |

## Tech stack

- Swift 5, SwiftUI, SwiftData, Swift Testing
- iOS 26.5+, Xcode 26.6
- Localized in English, Simplified Chinese (简体中文) and Japanese (日本語):
  UI strings in `Localizable.xcstrings`, app display name in `InfoPlist.xcstrings`
- Planned: AVFoundation (capture), Vision (face detection and person
  segmentation), Core Image / Metal (real-time filters), Photos (saving)

## Getting started

```sh
open "Maho Lens.xcodeproj"
```

Select the `Maho Lens` scheme and run on a physical device. The camera is not
available in the iOS Simulator.

## Project layout

```
Maho Lens/           App target (SwiftUI + SwiftData)
Maho LensTests/      Unit tests (Swift Testing)
Maho LensUITests/    UI tests (XCTest)
```

## License

Copyright © 2026 Kyle Zhao. All rights reserved.
