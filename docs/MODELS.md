# Maho Lens · Models, parameters and metrics

## Vision models

| Task | Model | Parameters |
| --- | --- | --- |
| Face detection (Focus Charm) | `VNDetectFaceRectanglesRequest` | default revision (3) on device; revision 2 in the Simulator, whose runtime lacks the neural-engine path; largest face wins |
| Person segmentation (Mist Barrier) | `VNGeneratePersonSegmentationRequest` | `qualityLevel` user-selectable: fast / balanced (default) / accurate; `outputPixelFormat: OneComponent8`; stills always use accurate; synthetic head-and-shoulders oval from the face when segmentation is unavailable |

Analysis runs on a serial queue and drops frames while busy, so the mask rate adapts to the device.

## Image pipeline

| Stage | Implementation | Parameters |
| --- | --- | --- |
| Capture | `AVCaptureVideoDataOutput`, BGRA, `videoRotationAngle 90`, mirrored for the front camera | format chosen by `FormatSelector`: tallest ≤ 1080p that supports the target rate; min/max frame duration locked to 1/30 or 1/60 |
| Blur | `CIGaussianBlur` on a 0.25× copy, scaled back, blended with `CIBlendWithMask` | sigma = 1.5 + strength × 10 at quarter resolution; mask softened with sigma 1.5 |
| Toning | `CITemperatureAndTint` | target neutral = 6500 − balance × 3500 K (positive balance warms) |
| Grayscale | `CIColorControls` | saturation 0 |
| Render | `CIContext(mtlDevice:)` into the `MTKView` drawable | sRGB working space, `cacheIntermediates: false`, render only when a new frame arrived |
| Stills | `AVCapturePhotoOutput`, `photoQualityPrioritization: .balanced` | same spells applied to the still with an accurate mask; JPEG quality 0.92 |

## Measured metrics

The dial shows preview, capture and analysis rates over a one-second window, render and analysis milliseconds; Settings exposes a copyable performance report with low/peak preview rates.

| Environment | Setting | Preview fps | Render ms | Analysis ms | Notes |
| --- | --- | --- | --- | --- | --- |
| iPhone 16e simulator (software Core Image) | 30 fps, no spells | 30 | 0.6 | 1 | demo portrait source |
| iPhone 16e simulator | 30 fps, Mist Barrier + Ember Veil | 23 | 3.3 | 41 | face rev 2 + synthetic mask; simulator numbers are not representative |
| iPhone 16e simulator | 60 fps, Mist + Ember + Mono | 25 | 3.3 | 43 | same caveat |
| iPhone 16e, front camera 1920×1080 (Kyle's device, 2026-10-07, timer-driven rendering) | 60 fps, Mist Barrier | 50.0 (peak 60.0) | 0.96 | 18.3 (29 analyses/s) | capture 58 fps; meets target |
| iPhone 16e, front camera 1920×1080 (same build) | 30 fps, Mist Barrier | 24.0 (peak 26.0) | 1.44 | 29.2 (21 analyses/s) | capture 29 fps; **below target by 1 fps** |
| iPhone 16e, after frame-driven rendering fix | 30 fps / 60 fps | _to be re-measured_ | | | the fix removes the timer/capture beat that cost 4–5 fps |

The device reports show the GPU is not the limit (about 1 ms per frame) and the camera delivers
29 and 58 fps. The lost frames came from the preview drawing on a display timer at the target rate:
with capture at 29 fps and a 30 Hz timer, frames periodically land two per tick and one is skipped.
Rendering is now triggered by frame arrival, so the preview rate should track the capture rate.

The 25 fps (at 30) and 50 fps (at 60) thresholds are encoded in `FrameRateSetting.minimumAcceptable` and drive the dial colour.
