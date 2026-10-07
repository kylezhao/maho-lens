# Maho Lens · Bug list

## Found and fixed during development

| # | Bug | How it was found | Fix |
| --- | --- | --- | --- |
| 1 | Warm and cool toning were swapped: `CITemperatureAndTint` warms when the *target* neutral is lower | Unit test on a neutral grey | Balance subtracted from 6500 K; test pins the direction |
| 2 | `MTKView` intercepted every tap in the top bar (FPS dial, settings, flip) while bottom controls worked | UI test, then a coordinate probe | `isUserInteractionEnabled = false` on the preview view; regression UI test taps the top bar |
| 3 | Running face detection and segmentation in one `perform` call made a segmentation failure discard the face result | Unit test on the fixture in the Simulator | Requests run separately with the last error recorded |
| 4 | Simulator cannot run segmentation or face-detection revision 3 ("E5RT is not supported") | Unit test diagnostics | Revision 2 in the Simulator and a synthetic oval mask from the face when segmentation is unavailable |
| 5 | Sparkle burst showed a stray star at rest | Simulator screenshot | Burst starts in its finished state |
| 6 | FPS dial text wrapped onto three lines, then collapsed the number vertically after a fixed-size fix | Simulator screenshots | Whole dial label laid out at natural size with layout priority |
| 7 | Spell chips overflowed the screen in a horizontal row | UI test could not reach Mist Barrier | Three-column grid, all five spells visible |
| 8 | Settings sheet failed to present right after dismissing the gallery sheet | UI test | Test waits for dismissal; the two sheets are independent state |
| 9 | Preview rate fell 4–5 fps below the capture rate on device (50 vs 58 at 60 fps, 24 vs 29 at 30 fps) although rendering took ~1 ms | Device performance reports | The MTKView drew on a display timer at the target rate, beating against the camera's rate; rendering is now triggered per captured frame |
| 10 | After the per-frame fix, 60 fps still read 46 while capture was 58 | Second device report | Draw calls hopped through the main thread and coalesced when SwiftUI was busy; rendering now goes directly into the Metal layer on the capture queue |

## Known issues

| # | Issue | Impact | Mitigation / next step |
| --- | --- | --- | --- |
| A | Device point-of-interest mapping for focus is derived for 90°-rotated, mirrored frames and verified only by unit tests on the corners | Focus might track the wrong point on some orientations | Confirm on hardware; add exposure/focus indicator |
| B | Front cameras on many iPhones have fixed focus | Focus Charm drives exposure only | Expected; documented in the UI |
| C | Segmentation mask lags the frame by one analysis interval | Slight halo on fast motion | Use `fast` quality or temporal smoothing of the mask |
| D | Simulator frame rates are not meaningful | Thresholds must be measured on device | Device performance report to be pasted into `MODELS.md` |
| E | Demo portrait is a third-party photo (Lorem Picsum id 1027, Unsplash licence) | Fine for a demo; not for shipping | Replace with an owned asset before release |
