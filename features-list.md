# Screenshot Utility — To-Do List

## 1. Screenshot Capture

- [x] **Area Screenshot** — Capture a user-selected screen region.
- [x] **Fullscreen Screenshot** — Capture the entire active display.
- [x] **Capture Delay** — Configurable delay before capture, defaulting to 0 seconds.
- [ ] **Scrolling Capture** — Capture a selected area continuously while scrolling, stopping when scrolling ends or the maximum height of 20,000 px is reached.
- [x] **Repeat Previous Screenshot** — Repeat the last capture using the same mode and selection.
- [x] **Multi-Display Support** — Automatically target the active display.
- [x] **Cursor Capture** — Option to include or exclude the mouse cursor.

## 2. Saving & File Management

- [x] **PNG Support** — Save screenshots as PNG.
- [x] **JPG Support** — Save screenshots as JPG.
- [x] **JPG Quality** — Configurable compression quality, defaulting to 80.
- [x] **Timestamp Filenames** — Generate filenames in the format `shot_YYYYMMDD_HHMMSS.png` (or `.jpg`).
- [x] **Default Save Location**
  - Read the preferred save location from system preferences, if available.
  - Otherwise, default to `~/Pictures/shots`.
  - Create the default directory if it does not exist.
- [x] **Save Location Settings** — Allow users to change the default output folder.
- [x] **Post-Capture Action** — Save to disk by default, with an option to copy directly to the clipboard.
- [x] **Reveal Latest Screenshot** — Open Finder with the most recently captured file selected.

## 3. OCR & Code Recognition

- [ ] **Unified Recognition Action** — Add a menu item named **OCR Recognition** that automatically detects the appropriate recognition mode based on the captured image.
- [ ] **OCR Text Recognition**
  - Extract text from screenshots.
  - Support multiple languages, prioritizing English and Polish.
- [ ] **QR Code Recognition** — Detect and decode QR codes.
- [ ] **Barcode Recognition** — Detect and decode 1D barcodes.
- [ ] **Native Recognition Framework** — Use Apple's Vision framework (`VNRecognizeBarcodesRequest`) on macOS 12+ for on-device QR and barcode recognition without heavy third-party dependencies.

## 4. Hotkeys & System Integration

- [x] **Global Keyboard Shortcuts** — Support customizable shortcuts for each capture mode.
  - Use [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for shortcut configuration and UI.
- [x] **Launch at Login** — Option to launch automatically when the user logs in.

## 5. Menu Bar & Screenshot History

- [x] **Menu Bar Integration** — Provide a dropdown panel showing the 5–10 most recent screenshots.
- [x] **Recent Screenshot Selection** — Select a recent screenshot to reveal its file in Finder.
- [ ] **Recent Screenshot Actions**
  - Copy the image to the clipboard.
  - Reveal the file in Finder.

