# Maho Lens · Optimizations

## Implemented

- **Orientation handled by the capture connection** (`videoRotationAngle`, `isVideoMirrored`), so Vision and Core Image never transform buffers and the whole pipeline thinks in upright frames.
- **Format selection locks the frame rate**: tallest format up to 1080p that supports 30 or 60, with min and max frame duration pinned, so the sensor never delivers more than the display can show.
- **Analysis off the hot path**: Vision runs on its own serial queue and drops frames while busy; the newest mask is reused until the next one lands. Capture and rendering never wait on segmentation.
- **Quarter-resolution blur**: the Gaussian blur runs on a 0.25× copy and is scaled back, roughly a 16× reduction in blur cost with a softer, lens-like fall-off.
- **Lazy Core Image graph, one GPU pass**: filters are composed as a `CIImage` graph and rendered once per frame straight into the `MTKView` drawable with a Metal command buffer; `cacheIntermediates` is off to save memory.
- **Render only on new frames**: the view ticks at the target rate but skips frames with no new content, so the measured preview rate is real and the GPU idles otherwise.
- **Thread-safe metrics with an unfair lock** and one-second sliding windows; the UI polls four times a second rather than observing every frame.
- **Stills reuse the live graph** with an accurate mask, so what you capture is what you saw.

## Candidates not yet done

- Run segmentation on a downscaled buffer and at `fast` quality by default on older devices, with a quality auto-switch when the preview rate drops below the threshold.
- Temporal smoothing of the mask (blend with the previous mask) to remove halo flicker.
- Replace the Gaussian blur with a disc (bokeh) kernel for a more photographic background.
- `AVCaptureVideoDataOutput` in YUV (`420f`) with a Core Image colour conversion to cut bandwidth versus BGRA.
- Metal compute shader for the blend and toning to drop Core Image overhead on 60 fps 1080p.
- Burst/HDR capture paths and Live Photo support.
