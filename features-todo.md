# Screenshot Utility — Recommended Development Order

Build in dependency order: establish the capture and saving pipeline first, then system integration, recognition, and finally convenience features. This minimizes rework and ensures every stage produces a usable application.

## Phase 1 — Core capture and saving

The first milestone is a working app that captures screenshots and saves them reliably.

- [x] 1\. PNG Support — Establish the image output pipeline.
- [x] 2\. Default Save Location — Read system preferences where available; otherwise use `~/Pictures/shots`. Create the directory if missing.
- [x] 3\. Timestamp Filenames — Use `shot_YYYYMMDD_HHMMSS.png` naming.
- 4\. Fullscreen Screenshot — Capture the entire active display.
- 5\. Area Screenshot — Let users select a screen region.
- 6\. Multi-Display Support — Correctly target the active display and handle display coordinates.
- 7\. Cursor Capture — Support including or excluding the cursor.
- 8\. Capture Delay — Configurable delay, defaulting to 0 seconds.
- 9\. JPG Support — Add JPEG encoding.
- 10\. JPG Quality — Configurable compression quality, defaulting to 80.
- 11\. Save Location Settings — Allow users to change the output folder.
- 12\. Post-Capture Action — Save to disk by default, with an option to copy directly to the clipboard.

Milestone: Both capture modes work reliably, with correct output files and configurable saving behavior.

## Phase 2 — Native macOS integration

Make the utility convenient to use without opening its main interface.

- 13\. Menu Bar Integration — Add a menu bar icon and dropdown panel.
- 14\. Global Keyboard Shortcuts — Add customizable shortcuts for each capture mode using [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- 15\. Launch at Login — Allow automatic startup.
- 16\. Repeat Previous Screenshot — Repeat the last capture mode and selection.
- 17\. Reveal Latest Screenshot — Reveal the most recent file in Finder.

Milestone: The app is usable as a native menu bar utility, primarily through shortcuts.

## Phase 3 — Screenshot history

Build history on top of the working save pipeline and menu bar.

- 18\. Recent Screenshot List — Display the 5–10 most recent screenshots.
- 19\. Recent Screenshot Selection — Reveal a selected screenshot in Finder.
- 20\. Recent Screenshot Actions — Copy an image to the clipboard or reveal its file in Finder.

Milestone: Users can quickly retrieve and reuse recent captures.

## Phase 4 — OCR and code recognition

Implement recognition as a separate capability so it doesn't complicate the initial capture pipeline.

- 21\. Native Recognition Framework — Use Apple's Vision framework for on-device recognition.
- 22\. QR Code Recognition — Detect and decode QR codes.
- 23\. Barcode Recognition — Detect and decode 1D barcodes.
- 24\. OCR Text Recognition — Extract text, prioritizing English and Polish.
- 25\. Unified Recognition Action — Add an OCR Recognition menu item that chooses the appropriate recognition mode based on the image.

Milestone: Users can extract text or decode supported codes directly from screenshots.

Implementation note: `VNRecognizeBarcodesRequest` is intended for barcode recognition. Text extraction uses Vision's text-recognition request, `VNRecognizeTextRequest`. Keep these as separate recognition paths behind the unified action.

## Phase 5 — Scrolling capture

- 26\. Scrolling Capture — Capture a selected region continuously while scrolling, stop when scrolling ends, and enforce a maximum output height of 20,000 px.

Why last? Scrolling capture is substantially more complex than ordinary screenshots. It may require scroll-event handling, repeated image capture, overlap detection, image stitching, and careful handling of fixed elements and changing content. It should build on a proven capture pipeline rather than delay the first usable release.

## Recommended release strategy

MVP — Essential screenshot utility

Phase 1, items 1–12

Capture, save, choose formats, and configure output.

Release 1.0 — Daily-use utility

Phases 1–3, items 1–20

Add shortcuts, menu bar access, repeat capture, and history.

Release 1.1 — Recognition

Phase 4, items 21–25

Add OCR, QR decoding, and barcode recognition.

Release 1.2 — Advanced capture

Phase 5, item 26

Add scrolling capture after validating its technical feasibility.

One architectural recommendation: Before implementing individual features, establish a shared capture service, a shared save service, and a capture-settings model. All capture modes should use the same saving pipeline, and keyboard shortcuts and menu bar actions should invoke the same underlying commands. This prevents duplicated logic and makes future features cheaper to implement.