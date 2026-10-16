# Shots & Impact

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Shots App Icon" />
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/shots/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_Release-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download Latest Release" />
  </a>
</p>

<p align="center">
  <strong>The ultra-fast, zero-dependency macOS screen capture suite and precision vector annotation engine.</strong>
</p>

<p align="center">
  Capture pixel-perfect screenshots, stitch infinite scrolling windows, extract on-screen text and barcodes instantly, and mark up visuals on an elastic expanding canvas—powered entirely by native Swift and AppKit.
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-GPL_v2.0-blue?style=flat-square" alt="License: GPL v2.0" />
  </a>
  <img src="https://img.shields.io/badge/Platform-macOS_12.0+-lightgrey?style=flat-square&logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Swift-5.7+-orange?style=flat-square&logo=swift" alt="Swift 5.7+" />
  <img src="https://img.shields.io/badge/Architecture-Universal_Native-black?style=flat-square" alt="Universal Native" />
  <img src="https://img.shields.io/badge/Tests-99_Passing-brightgreen?style=flat-square" alt="99 Passing Tests" />
  <img src="https://img.shields.io/badge/Dependencies-Zero-success?style=flat-square" alt="Zero Dependencies" />
</p>

---

## Why Shots?

Screen capture on macOS is often trapped between two extremes: minimal system shortcuts that leave you stranded without markup tools, or heavy, subscription-gated electron apps that consume hundreds of megabytes of RAM and send your data to third-party clouds.

**Shots** delivers a comprehensive, privacy-first capture suite accompanied by **Impact**, a companion vector annotation studio. Designed as lightweight native macOS binaries, they launch instantaneously, operate entirely offline, and provide pro-tier workflows from a discreet menu bar icon.

* **100% Offline & Private**: Apple Vision on-device OCR and local image rendering guarantee that not a single pixel or extracted token ever leaves your machine.
* **Instantaneous Responsiveness**: Pure AppKit and CoreGraphics pipelines ensure zero launch latency, instant crosshair reticle drawing, and fluid 60 FPS canvas interactions.
* **Elastic Canvas Architecture**: Annotations are never constrained by the original screenshot boundary. Draw beyond the frame and the canvas naturally expands with smart padding.
* **Dual-Application Synergy**: **Shots.app** handles hotkey orchestration, multi-display captures, and diagnostic measurement overlays; **Impact.app** provides dedicated, non-destructive vector manipulation and quick export.

---

## Key Capabilities

### 🔍 Precision Capture & Diagnostic Overlays
- **Precision Reticle & Coordinate Badges**: High-contrast reticle crosshairs display real-time pixel coordinates and dimensions without activating background windows or disrupting open menus.
- **Freeze-Screen Capture**: Freeze dynamic screen states, tooltips, and hovering dropdowns instantly with customizable countdown HUDs.
- **Interactive Screen Ruler (`⌘⇧M`)**: Drag alignment guidelines across any window to measure horizontal width, vertical height, and diagonal Euclidean distance in physical pixels.
- **Magnified Color Loupe (`⌘⇧C`)**: Hover anywhere on screen to inspect an interactive 9×9 pixel grid with centered sample reticles, instant RGB/HEX readouts, and one-click clipboard copying.

### 📜 Automated Infinite Scrolling Capture (`⌘⇧5`)
- **Algorithmic Shift Detection**: Captures long documents, web pages, code listings, and chats by analyzing consecutive frames with sub-pixel coarse-to-fine differential matching.
- **Scrollbar & Gutter Suppression**: Automatically filters window scrollbars and editor gutters to prevent ghosting artifacts during stitching.
- **High-Capacity Assembly**: Stitches continuous vertical compositions up to 20,000 pixels in height with strict memory bounds and runaway loop protection.

### ⚡ Instant OCR, QR & Barcode Recognition (`⌘⇧R`)
- **On-Device Vision Intelligence**: Automatically identifies and decodes text, QR codes, and 1D barcodes directly from a screen marquee.
- **Broad Symbology Support**: Decodes Code 128, Code 39, Code 93, EAN-13, EAN-8, UPC-E, Codabar, and ITF-14.
- **Accurate Multi-Language OCR**: High-precision text extraction with automated language correction, prioritizing English and Polish text models.
- **HUD Notification & Instant Clipboard**: Copies extracted payloads directly to your pasteboard while displaying a transient, non-activating confirmation HUD.

### 🎨 Impact: Vector Annotation Studio
- **Elastic Canvas**: Add annotations, arrows, or callout badges that extend outside the captured image boundary; the canvas dynamically expands with a 10px breathing margin and contracts cleanly on deletion.
- **3-Point Quadratic Bezier Arrows (`A`)**: Create curved arrows with dynamic curvature retention that maintain proportional arc geometry when stretched or reoriented.
- **Auto-Incrementing Counter Badges (`C`)**: Drop sequential numbered badges that calculate the next integer in sequence and feature draggable directional pointer tails.
- **Single-Layer Multi-Hole Spotlight (`S`)**: Darken the image with a unified 50% mask and punch clean, rounded rectangular focus windows across points of interest.
- **Privacy Redaction Blur (`B`)**: Apply localized Gaussian blur filters to redact sensitive tokens, passwords, or faces, featuring interactive 8-point resize handles and 10px boundary catchment dragging.
- **Smooth Vector Ink & Highlighter (`P` / `H`)**: Natural quadratic Bezier ink curves with pre-draw footprint previews and multiply-blend highlighting.
- **Non-Destructive Numbered Saves**: Closing or saving from Impact writes directly to collision-free numbered files (e.g. `capture-2.png`, `capture-3.png`) without overwriting your original file.

---

## How It Works

```text
1. Trigger Capture       Select Region, Fullscreen, Scrolling Window, Ruler, or OCR via Global Hotkeys
2. Frame & Measure       Use the precision reticle, alignment guides, or 9x9 color loupe
3. Review & Annotate     Impact opens instantly with vector tools on an elastic auto-expanding canvas
4. Export & Share        Compositions auto-save to disk with numbered versioning and copy to the clipboard
```

---

## Keyboard Shortcuts

### Shots (Global System Shortcuts)

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Area Capture** | `⌘ ⇧ 4` | Interactive crosshair selection with dimension badges |
| **Fullscreen Capture** | `⌘ ⇧ 2` | Captures active display or selected screen |
| **Repeat Previous** | `⌘ ⇧ 3` | Repeats last screenshot at the identical coordinates |
| **OCR / Barcode** | `⌘ ⇧ R` | Extracts text, QR codes, or barcodes to clipboard |
| **Scrolling Capture** | `⌘ ⇧ 5` | Auto-scrolls and stitches continuous vertical windows |
| **Screen Ruler** | `⌘ ⇧ M` | Measures pixel width, height, and diagonal distance |
| **Color Picker** | `⌘ ⇧ C` | Magnifies 9×9 pixel grid and copies HEX/RGB values |
| **Preferences** | `⌘ ,` | Opens settings, hotkey recorder, and permissions |

### Impact (Annotation Studio)

| Tool / Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Pointer (Select)** | `V` | Selects, translates, and manipulates element handles |
| **Curved Arrow** | `A` | 3-point quadratic Bezier curve with curvature control |
| **Line** | `L` | Straight segment with Shift-constrained 45° snapping |
| **Rectangle** | `R` | Rounded rectangle with outline, solid, or striped styles |
| **Oval / Ellipse** | `O` | Proportional or freeform elliptical bounding layer |
| **Spotlight** | `S` | Darkened mask with punched transparent highlight holes |
| **Step Counter** | `C` | Auto-incrementing numbered badge with pointer tail |
| **Freehand Pen** | `P` or `D` | Opaque smooth vector ink with nib preview |
| **Highlighter** | `H` | Translucent multiply-blended freehand marker |
| **Privacy Blur** | `B` or `U` | Localized Gaussian blur with 8-point resize handles |
| **Ruler** | `M` | Calibrated dimension measurement marker |
| **Zoom In / Out** | `⌘ +` / `⌘ -` | Incremental zoom (or `⌘` + Scroll / Trackpad pinch) |
| **Actual Size / Fit** | `⌘ 0` / `⌘ 1` | Resets canvas to 100% or scales to fit window |
| **Pan Canvas** | `Right-Drag` | Pans the document view with closed-hand cursor |
| **Copy Composition**| `⌘ C` | Flattens composition and copies PNG to pasteboard |
| **Save Image** | `⌘ S` | Saves flattened image with auto-incremented name |
| **Open File** | `⌘ O` | Opens an existing image in a new editor window |
| **Undo / Redo** | `⌘ Z` / `⌘ ⇧ Z` | Full history snapshots for all layer operations |
| **Two-Stage Esc** | `Esc` | Deselects active layers / tools, second press closes window |
| **Safe Exit** | `⌘ Q` × 2 | Double-tap confirmation prompt prevents accidental quits |

---

## What Makes It Different

| Feature | Generic Screen Capture Tools | Shots & Impact |
| :--- | :--- | :--- |
| **Runtime Footprint** | 200MB+ (Electron / Chromium wrapper) | **Zero external dependencies, pure native AppKit** |
| **Annotation Boundaries**| Cropped strictly to screenshot dimensions | **Elastic expanding canvas with dynamic padding** |
| **Text Recognition** | Cloud API or external binary CLI required | **Native Apple Vision OCR, QR & 10+ 1D barcode types** |
| **Scrolling Capture** | Fragile DOM injection or browser-only | **Synthetic event stream with auto-offset stitching** |
| **File Overwriting** | Overwrites captures or forces Save As modal | **Automatic collision-free numbered file versioning** |
| **Accidental Exit** | Single `⌘Q` loses unsaved work | **Two-stage `Esc` lifecycle and double-tap `⌘Q` safeguard** |

---

## Quick Start

### Prerequisites
- macOS 12.0 (Monterey) or later
- Swift 5.7+ command-line tools (`xcode-select --install`)

### Compile and Launch
Clone the repository and run both applications directly from your terminal:

```bash
git clone https://github.com/unamatasanatarai/shots.git
cd shots
make run
```

`make run` compiles both `build/Impact.app` and `build/Shots.app`, signs the bundles locally, refreshes the macOS LaunchServices cache, and launches Shots into your menu bar.

### Launch Standalone Editor
To open Impact with an image for annotation:

```bash
make run-impact IMAGE=/path/to/screenshot.png
```

---

## Automated Test Suite

The codebase includes an extensive native CLI unit and stress test suite executing directly via `swiftc` without external testing dependencies.

```bash
# Run Shots capture, storage, and stress test suites (53 tests)
make test-shots

# Run Impact vector geometry, tool lifecycle, and canvas tests (46 tests)
make test-impact
```

**Verified Test Coverage (99 Tests Passing):**
- **Stress & Throughput**: Concurrent 8K UHD encoding benchmarks, 50 concurrent same-second disk writes without collision, sub-150ms indexing of 1,000-file directories, and 60-frame continuous stitching clamped at 20,000px.
- **Mathematical Integrity**: Quadratic Bezier curvature preservation, 8-handle rectangular catchment mechanics, and negative-origin multi-monitor desktop geometry.
- **Security & Permissions**: Strict enforcement of Screen Recording and Accessibility checks before activating screen overlays.

---

## Makefile Automation

| Command | Action |
| :--- | :--- |
| `make run` | Rebuilds both Shots & Impact and launches Shots in the menu bar |
| `make build-shots` | Compiles `build/Shots.app`, generates `Info.plist`, and code-signs bundle |
| `make build-impact` | Compiles `build/Impact.app`, generates `Info.plist`, and code-signs bundle |
| `make run-impact` | Compiles and launches Impact (pass `IMAGE=path` to open immediately) |
| `make dmg` | Generates a styled, branded Retina `.dmg` installer with custom layout |
| `make test-shots` | Executes the 53-assertion native test suite for Shots |
| `make test-impact` | Executes the 46-assertion annotation engine test suite for Impact |
| `make release <ver>` | Validates tests, bumps version, builds DMG, tags git, and creates GitHub release |
| `make reset-cache` | Revokes TCC permissions and rebuilds macOS LaunchServices / Icon caches |
| `make clean` | Removes all temporary binaries and build directories |

---

## Distribution Packaging

Create a styled macOS distribution `.dmg` featuring high-DPI Retina background artwork, custom window dimensions, and pre-aligned drag-and-drop links to `/Applications`:

```bash
make dmg
open build/
```

Both `Shots.app` and `Impact.app` are bundled side-by-side inside the installer.


---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE).
