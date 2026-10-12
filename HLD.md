```markdown
# Project High-Level Design (HLD)

## 1. Executive Summary

### 1.1 Purpose of the System
The **Screenshot (macOS)** project is a specialized, native macOS desktop utility engineered to deliver zero-friction, ultra-low-latency screen capture supporting both fullscreen and interactive region selection[cite: 1]. Operating as an accessory agent (`LSUIElement`), the application resides exclusively in the macOS menu bar status item area with zero presence in the macOS Dock or `Cmd+Tab` task switcher[cite: 1]. It pairs native Carbon global hotkey interception with Apple CoreGraphics display capture, multi-monitor display routing, and an interactive region selection overlay.

### 1.2 Core Business Objectives
* **Frictionless Screen Capture**: Provide near-instantaneous screen capture via a global hardware keyboard trigger without requiring elevated macOS Accessibility (TCC) privileges[cite: 1].
* **Minimal Resource and UI Footprint**: Eliminate clutter by operating without a Dock icon, maintaining a memory footprint under 35 MB in idle state, and utilizing transient overlay windows[cite: 1].
* **Streamlined Workflow Delivery**: Offer simultaneous multi-channel output—instant clipboard transfer and formatted disk persistence (PNG only).
* **Customizability**: Allow end-users to rebind hotkey combinations and define custom destination storage trees[cite: 1].

### 1.3 Intended Users
* Power users, software engineers, QA analysts, and content creators requiring high-cadence, non-disruptive screen capture with immediate clipboard synchronization and disk archiving across single and multi-monitor macOS environments[cite: 1].

### 1.4 High-Level Architectural Overview
The system follows a native, event-driven modular desktop architecture implemented in Swift, AppKit, SwiftUI, and low-level C-based macOS system frameworks (CoreGraphics, Carbon HIToolbox)[cite: 1]. The application lifecycle is governed by an `NSApplication` instance configured with an `.accessory` activation policy[cite: 1]. Core modules operate under a singleton-based service coordinator pattern decoupled by Combine reactive properties, NotificationCenter events, and AppKit target-action bindings[cite: 1].


```

+-------------------------------------------------------------------------------+
|                                  macOS System                                 |
|   (Display Services, Carbon Event Loop, Pasteboard, File System, TCC Engine)  |
+-------------------------------------------------------------------------------+
▲
│ System APIs
▼
+-------------------------------------------------------------------------------+
|                           Screenshot Application Core                         |
|                                                                               |
|  [ Carbon Hotkey Interceptor ] ──> [ Capture Orchestrator ]                   |
|                                             │                                 |
|  [ Status Bar Controller ] ───────────────┤                                 |
|         │                                   ▼                                 |
|         │                        [ CoreGraphics Engine ]                      |
|         ▼                                   │                                 |
|  [ Settings & State (Defaults) ]             ├──> [ Region Selection Overlay ] |
|         ▲                                   ├──> [ Storage & IO Manager ]     |
|         │                                   └──> [ Pasteboard Sync Engine ]   |
|  [ SwiftUI Preferences Host ]                                                 |
+-------------------------------------------------------------------------------+

```

### 1.5 Scope of the Recreation Effort
* **In-Scope**:
  * Complete reconstitution of the macOS menu bar daemon (`LSUIElement = true`)[cite: 1].
  * Global hotkey capture engine using native Carbon `HIToolbox` event handlers[cite: 1].
  * Active display detection across arbitrary multi-monitor topologies based on cursor coordinates[cite: 1].
  * Interactive rectangular region/marquee selection with crosshair dragging and real-time dimension overlay.
  * High-DPI / Retina-aware frame rasterization into **PNG format only**.
  * Dual-output pipeline: direct disk serialization with dynamic ISO-standard timestamping and system pasteboard synchronization[cite: 1].
  * Quick toggle controls in the status menu for disk save and clipboard copy[cite: 1].
  * User preferences panel built in SwiftUI with local keyboard event monitoring for hotkey recording[cite: 1].
* **Out-of-Scope (for Initial Reconstruction)**:
  * In-app image markup, drawing, and annotation tools[cite: 1].
  * Remote cloud storage integrations (e.g., S3, Google Drive, Imgur, Cloudinary)[cite: 1].
  * Video/screen recording and animated GIF generation[cite: 1].
  * Floating preview HUD / thumbnail windows and visual/audio feedback triggers.

---

## 2. System Overview

### 2.1 System Description
The project is a lightweight client-side daemon designed for macOS 12.0 (Monterey) and later[cite: 1]. It starts silently at launch, verifies Screen Recording permissions against macOS Transparency, Consent, and Control (TCC), registers a process-independent global hotkey hook into the Carbon Event Target, mounts a template icon into the system menu bar, and waits for capture events[cite: 1].

Upon trigger, the user can capture either the active screen or drag a crosshair selection rectangle to isolate a custom region. The engine captures the target frame buffer into a `CGImage`, writes the lossless PNG image to disk and clipboard according to user configuration[cite: 1].

### 2.2 Major Capabilities
* **Accessory Agent Lifecycle**: Silent background operation with zero task-switching visibility[cite: 1].
* **Global Hotkey Interception**: Unprivileged global key combination capture with collision detection[cite: 1].
* **Interactive Region Marquee Selection**: Precise mouse-drag selection with crosshair cursor support and coordinate clamping.
* **Multi-Display Resolution**: Dynamic coordinate translation to isolate display frames across multi-monitor setups[cite: 1].
* **Retina Frame Rasterization**: Full-resolution bitmap capture supporting lossless PNG format[cite: 1].
* **Concurrent Output Routing**: Atomic file writing to user-selected filesystem paths and multi-flavor pasteboard updates[cite: 1].
* **Live Configuration Management**: Persistent configuration with dynamic menu updates and reactive preference binding[cite: 1].

### 2.3 Key Modules
| Module Name | Swift File Source | Primary Responsibility |
| :--- | :--- | :--- |
| **App Lifecycle** | `main.swift`, `AppDelegate.swift` | Bootstraps `NSApplication`, sets `.accessory` activation policy, preflights TCC permissions, initializes controllers[cite: 1]. |
| **State & Settings** | `AppSettings.swift` | Encapsulates app configuration backed by `UserDefaults`; notifies downstream observers via Combine `@Published` and `NotificationCenter`[cite: 1]. |
| **Menu Bar Controller** | `StatusBarController.swift` | Manages `NSStatusItem`, renders vector/SF Symbol icons, builds dynamic menu with checkmark toggles and hotkey labels[cite: 1]. |
| **Capture Orchestrator** | `CaptureManager.swift` | Resolves target display or region coordinates, calls frame capture APIs, dispatches disk and pasteboard tasks[cite: 1]. |
| **Hotkey Engine** | `HotkeyManager.swift`, `KeyCodes.swift` | Installs Carbon event handlers, maps key codes and modifier masks, handles system registration conflicts[cite: 1]. |
| **Region Selection HUD** | `RegionSelectionOverlay.swift` | Fullscreen transparent overlay capturing mouse down, drag, and up events to render a selection marquee with crosshairs. |
| **Preferences UI** | `PreferencesWindowController.swift`, `PreferencesView.swift` | Hosts SwiftUI preference interface, monitors local key events for hotkey recording, manages directory selection sheets[cite: 1]. |

### 2.4 External Dependencies
* **Apple Cocoa / AppKit Framework**: Core macOS UI, windowing (`NSWindow`), status bar (`NSStatusBar`), pasteboard (`NSPasteboard`), application management (`NSApplication`)[cite: 1].
* **Apple CoreGraphics Framework**: Low-level display management, screen geometry resolution (`CGDirectDisplayID`), and display image cropping/capture (`CGDisplayCreateImage`, `CGWindowListCreateImage`)[cite: 1].
* **Apple Carbon / HIToolbox Framework**: Low-level global keyboard event handling (`RegisterEventHotKey`, `InstallEventHandler`, `kEventClassKeyboard`)[cite: 1].
* **Apple SwiftUI / Combine Framework**: Declarative preference view construction, reactive event pipelines, and settings observation[cite: 1].

### 2.5 Architectural Style
* **Architectural Pattern**: Event-Driven Desktop Agent with Modular Service Facades[cite: 1].
* **Communication Paradigm**: Direct invocation, closure callbacks (`onTrigger`), Combine reactive publishers (`@Published`), AppKit Target-Action patterns, and `NotificationCenter` broadcasts[cite: 1].
* **Concurrency Model**: Main RunLoop (`DispatchQueue.main`) for UI, window management, and Carbon events, with off-thread asynchronous dispatching for disk I/O and pasteboard payload generation[cite: 1].

---

## 3. Functional Requirements

### 3.1 Feature Requirements Matrix

| ID | Requirement Category | Description | Implementation Target |
| :--- | :--- | :--- | :--- |
| **FR-01** | **Lifecycle & Dock** | Application must execute as an accessory process without appearing in the macOS Dock or `Cmd+Tab` switcher[cite: 1]. | `LSUIElement = true`, `NSApp.setActivationPolicy(.accessory)`[cite: 1] |
| **FR-02** | **Menu Bar Status Item** | Display a dynamic status bar icon in the macOS menu bar using SF Symbol `camera.viewfinder`[cite: 1]. | `NSStatusBar.system.statusItem`, `isTemplate = true`[cite: 1] |
| **FR-03** | **Global Hotkey** | Support global hotkey capture from any foreground macOS application without requiring Accessibility privileges[cite: 1]. | Carbon HIToolbox `RegisterEventHotKey`[cite: 1] |
| **FR-04** | **Default Hotkey** | Default global hotkey combination must be `⌘ ⇧ 1` (Command + Shift + 1)[cite: 1]. | Key code `18` (`kVK_ANSI_1`), Modifiers: `cmdKey \| shiftKey`[cite: 1] |
| **FR-05** | **Custom Hotkey Recorder** | Users can record custom key combinations with modifier validation, handling special keys (Esc to cancel, Delete to reset)[cite: 1]. | Local event monitor intercepting `keyDown` and `flagsChanged`[cite: 1] |
| **FR-06** | **Region & Fullscreen Capture**| Support both fullscreen capture of the active display under the cursor and interactive marquee region selection via crosshair dragging. | `RegionSelectionOverlay` + `CGDisplayCreateImage` / cropping |
| **FR-07** | **Retina Frame Rasterization** | Capture display frames at full hardware resolution buffer in lossless PNG format[cite: 1]. | `CGDisplayCreateImage` encoded to PNG `NSBitmapImageRep` |
| **FR-08** | **Disk Persistence** | Format captured bitmap into lossless PNG; save with timestamp pattern `Screenshot yyyy-MM-dd at HH.mm.ss.png`[cite: 1]. | Configurable path (default `~/Pictures/Screenshots`)[cite: 1] |
| **FR-09** | **Clipboard Transfer** | Place captured image onto the general pasteboard concurrently in native image, PNG data, and file URL formats[cite: 1]. | `NSPasteboard.general.writeObjects`[cite: 1] |
| **FR-10** | **Quick Toggle Controls** | Provide instant toggle checkboxes in status menu for disk save and clipboard copy[cite: 1]. | Dynamic `NSMenu` binding to `AppSettings`[cite: 1] |
| **FR-11** | **Preferences Window** | Floating settings window allowing destination folder selection via native dialog, hotkey recording, and TCC status checking[cite: 1]. | `NSHostingController<PreferencesView>`[cite: 1] |
| **FR-12** | **TCC Permission Persistence** | Ensure Screen Recording permission state is sustained between app runs and binary rebuilds using stable code signing identities. | Developer ID / fixed Development Team ID configuration in project build settings |

---

## 4. Non-Functional Requirements

### 4.1 System NFR Specifications


```

+--------------------------------------------------------------------------------+
|                           NON-FUNCTIONAL REQUIREMENTS                          |
+------------------------------------+-------------------------------------------+
| Latency to First Pixel on Screen   | ≤ 150 ms from hotkey trigger to capture   |
| Idle Memory Footprint              | ≤ 35 MB Resident Set Size (RSS) |
| Active Capture Memory Overhead     | Transient spike ≤ 120 MB (released <1.5s) |
| Binary Distribution Footprint      | ≤ 5 MB standalone executable/app bundle   |
| macOS Version Compatibility        | macOS 12.0 (Monterey) up to macOS 15+     |
| CPU Utilization (Idle)             | 0.0% (Zero RunLoop polling)     |
+------------------------------------+-------------------------------------------+

```

### 4.2 Quality Attribute Details
* **Performance & Responsiveness**:
  * The latency between the global hotkey press and the initiation of the capture sequence must not exceed 50 milliseconds[cite: 1].
  * Image encoding (PNG) and disk serialization must not block the main RunLoop or stall user interaction[cite: 1].
* **Reliability & Fault Tolerance**:
  * Failure to write to disk (e.g., full disk, permissions denied) must not prevent clipboard population or trigger an unhandled application crash[cite: 1].
* **Resource Management**:
  * Image representations (`CGImage`, `NSBitmapImageRep`, `NSImage`) must be deallocated promptly after serialization to prevent memory leaks during repeated rapid captures[cite: 1].

---

## 5. Assumptions and Constraints

| Category | Type | Description | Rationale / Mitigation |
| :--- | :--- | :--- | :--- |
| **Platform** | Constraint | Target OS is strictly macOS (>= 12.0)[cite: 1]. | Relies exclusively on macOS-native frameworks (`AppKit`, `CoreGraphics`, `Carbon`)[cite: 1]. |
| **Image Format** | Constraint | Output image format is restricted strictly to lossless PNG. | Eliminates unnecessary complexity and encoder overhead. |
| **Hotkey System** | Constraint | Carbon `HIToolbox` (`RegisterEventHotKey`) is used for global keys[cite: 1]. | Bypasses Accessibility TCC permissions requirement (`AXIsProcessTrusted`)[cite: 1]. |
| **Sandboxing** | Constraint | Project is distributed unsandboxed (`com.apple.security.app-sandbox` omitted)[cite: 1]. | Sandboxed apps cannot write to arbitrary directories like `~/Pictures/Screenshots` without Security-Scoped Bookmarks[cite: 1]. |
| **TCC Permissions** | Constraint | User must grant "Screen Recording" permission in System Settings[cite: 1]. Permissions must remain stable across builds via consistent code-signing credentials. | macOS security model requires explicit user consent[cite: 1]; stable Team ID prevents signature hash changes from triggering re-prompts. |

---

## 6. Proposed Architecture

### 6.1 Logical Architecture
The application is structured into four primary logical tiers:

1. **System Integration & Ingestion Tier**: Interfaces with the macOS Kernel and WindowServer. Encapsulates Carbon event dispatching, CoreGraphics screen enumeration, and pasteboard services[cite: 1].
2. **Orchestration & Coordination Tier**: Coordinates capture workflows. Evaluates settings, manages region selection or fullscreen captures, and broadcasts output jobs to storage and clipboard layers[cite: 1].
3. **Presentation & Interaction Tier**: Houses the user-facing interfaces: status bar menu (`AppKit`), region selection overlay (`AppKit`), and preferences dialog (`SwiftUI`)[cite: 1].
4. **State & Persistence Tier**: Manages reactive configuration state backed by `UserDefaults` and file system operations[cite: 1].


```

+--------------------------------------------------------------------------------+
|                        LOGICAL ARCHITECTURE TIERS                              |
+--------------------------------------------------------------------------------+
|                                                                                |
|  [ PRESENTATION TIER ]                                                         |
|    - StatusBarController (AppKit Menu Bar & Status Item)                       |
|    - RegionSelectionOverlay (AppKit Crosshair & Marquee Window)                |
|    - PreferencesWindowController & View (AppKit Window + SwiftUI Settings)     |
|                                                                                |
|                                        ▲                                       |
|                                        │ UI Events & Presentation              |
|                                        ▼                                       |
|  [ ORCHESTRATION & COORDINATION TIER ]                                         |
|    - AppDelegate (App Lifecycle & Route Wiring)                                |
|    - CaptureManager (Screen Selection, Frame Acquisition, Output Fan-out)      |
|    - HotKeyManager (Carbon Callback Dispatcher)                                |
|                                                                                |
|                   ▲                                            ▲               |
|                   │ State Access                               │ IO / System   |
|                   ▼                                            ▼               |
|  [ STATE & PERSISTENCE TIER ]             [ SYSTEM INTEGRATION TIER ]          |
|    - AppSettings (ObservableObject)         - Carbon HIToolbox (Hotkeys)       |
|    - UserDefaults Persistence               - CoreGraphics (Display Capture)   |
|    - Local File System (PNG)                - NSPasteboard General             |
|    - TCC Screen Recording Preflight         - Code Signing (Team ID Persistence)|
|                                                                                |
+--------------------------------------------------------------------------------+

```

### 6.2 Runtime Architecture & Execution Lifecycle
1. **Bootstrap Phase**:
   - `main.swift` initializes `NSApplication.shared`[cite: 1].
   - `NSApp.setActivationPolicy(.accessory)` removes the app from the Dock[cite: 1].
   - `CGPreflightScreenCaptureAccess()` verifies TCC authorization[cite: 1].
   - `HotKeyManager` registers the global shortcut `⌘ ⇧ 1`[cite: 1].
2. **Event Trigger Phase**:
   - User inputs hotkey or clicks the menu item[cite: 1].
   - `CaptureManager` presents the `RegionSelectionOverlay` (or initiates fullscreen capture depending on configuration).
3. **Region Marquee Selection Phase**:
   - Fullscreen transparent overlay displays custom crosshair cursor.
   - User drags mouse to define a rectangular marquee bounding box with live dimension tooltips.
   - On mouse release, the bounding box coordinates are converted to screen pixel coordinates.
4. **Capture & Fan-out Phase**:
   - `CGDisplayCreateImage` or `CGWindowListCreateImage` captures the buffer, cropped to the selected rectangle.
   - Encodes bitmap into PNG data[cite: 1].
   - Writes PNG binary data to `~/Pictures/Screenshots/`[cite: 1].
   - Clears and populates `NSPasteboard.general` with image data and file URL[cite: 1].

---

## 7. Frontend Architecture

### 7.1 UI Component Hierarchy & Organization

```text
Presentation Layer
├── Status Bar Component (AppKit)
│   ├── NSStatusItem (System Tray Icon: "camera.viewfinder")[cite: 1]
│   └── NSMenu (Dropdown List)[cite: 1]
│       ├── Capture Region MenuItem (Key Equivalent: ⌘⇧1)
│       ├── Separator
│       ├── Toggle: Save to Folder (Checked / Unchecked)[cite: 1]
│       ├── Toggle: Copy to Clipboard (Checked / Unchecked)[cite: 1]
│       ├── Separator
│       ├── Preferences & Hotkeys... (Key Equivalent: ⌘,)[cite: 1]
│       ├── Open Screenshots Folder (Key Equivalent: ⌘O)[cite: 1]
│       └── Quit Screenshot (Key Equivalent: ⌘Q)[cite: 1]
│
├── Region Selection Component (AppKit)
│   └── RegionSelectionOverlay (NSWindow)
│       ├── Level: .screenSaver
│       ├── Properties: Borderless, Transparent, Custom Crosshair Cursor
│       └── Actions: MouseDown, MouseDragged, MouseUp (Marquee Rendering & Crop)
│
└── Preferences Component (AppKit + SwiftUI)
    └── PreferencesWindowController (NSWindowController)[cite: 1]
        └── NSWindow (Titled, Closable, Miniaturizable, Floating)[cite: 1]
            └── NSHostingController[cite: 1]
                └── PreferencesView (SwiftUI)[cite: 1]
                    ├── Header (Branding & Subtitle)[cite: 1]
                    ├── Global Shortcut Box (Interactive Hotkey Recorder & Reset)[cite: 1]
                    ├── Storage Box (Path Chooser, Reveal Folder)[cite: 1]
                    ├── Behavior Box (2 Dynamic State Toggles)[cite: 1]
                    ├── System Permissions Box (TCC Preflight Status & Deep Link)[cite: 1]
                    └── Footer ("Done" Button)[cite: 1]

```

---

## 8. Backend Architecture (System Engine & Core Processing)

### 8.1 Module Breakdown & Responsibilities

* **Region Selector Engine**: Intercepts mouse coordinates across all displays, mapping drag gestures into absolute screen rectangles.
* **Rasterization Engine**: Acquires display frame buffer via CoreGraphics and crops pixels strictly to PNG format.


* **Output Dispatcher**: Writes PNG files to disk and synchronizes multiple pasteboard representations (`NSPasteboard.general`).



---

## 9. Database Design Overview (Persistent State & Storage Schema)

### 9.1 Entity Schema Definition (`UserDefaults`)

| Key Name | Storage Type | Default Value | Description / Permitted Values |
| --- | --- | --- | --- |
| `hotkeyKeyCode` | `Integer` | `18` | Virtual keycode representing shortcut trigger (18 = ANSI '1').

 |
| `hotkeyModifiers` | `Integer` | `384` (`cmdKey | shiftKey`) | Carbon modifier bitmask (`cmdKey = 256`, `shiftKey = 512`).

 |
| `saveToDisk` | `Boolean` | `true` | Governs whether screenshots are written to filesystem.

 |
| `saveDirectoryPath` | `String` | `~/Pictures/Screenshots` | Absolute or tilde-prefixed local filesystem directory.

 |
| `copyToClipboard` | `Boolean` | `true` | Governs whether captured images are copied to system pasteboard.

 |

---

## 10. Security & Permission Persistence Architecture

### 10.1 Sustaining TCC Permissions Between Builds

macOS tracks Screen Recording permissions via the application's code signature hash (incorporating the Bundle Identifier and Developer Team ID). To prevent permissions from resetting on every build or code modification:

1. **Consistent Signing Identity**: Always sign builds using a persistent Developer ID or a fixed local Apple Development certificate associated with a stable Team ID (`codesign -s "Apple Development: Name (TEAMID)"`).
2. **Stable Bundle Identifier**: Maintain a fixed bundle identifier (`com.local.ScreenshotApp`) across all development and production releases.
3. **Hardened Runtime & Entitlements**: Ensure appropriate entitlements are embedded so that TCC state bindings remain unbroken across binary updates.

---

## 11. Infrastructure, Build & Deployment

### 11.1 Build & Packaging Pipeline (`build.sh`)

```bash
# Compilation Command with strict PNG-only configuration
swiftc -O \
    Sources/ScreenshotApp/*.swift \
    -framework Cocoa \
    -framework Carbon \
    -framework SwiftUI \
    -o "build/Screenshot.app/Contents/MacOS/ScreenshotApp"

# Metadata Transfer
cp Resources/Info.plist "build/Screenshot.app/Contents/Info.plist"

# Consistent Code Signing to preserve TCC Permissions
codesign --force --deep --sign "Apple Development" --entitlements Resources/Entitlements.plist "build/Screenshot.app"

```

```

```