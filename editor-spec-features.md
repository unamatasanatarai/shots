# Comprehensive Specification: Native macOS Image Annotation Engine

## 1. Native macOS System Architecture

To achieve near-zero latency, high-performance rendering, and a native feel, the application must adhere to the following Apple framework constraints:

* **Window Management (AppKit):** Bypass standard `NSWindow` chrome. The editor must run in a borderless, transparent, floating `NSPanel` using `NSWindow.Level.floating` or `.screenSaver` to float above other desktop windows.
* **Capture Engine (ScreenCaptureKit):** Utilize macOS `ScreenCaptureKit` for high-performance, low-latency screen recording and image capture, which is essential for capturing scrolling regions.
* **Rendering Pipeline (CoreGraphics / Metal):** Rely on `CoreGraphics` (CGContext) or Metal for the rendering pipeline. Avoid standard SwiftUI view hierarchies for the canvas layers to guarantee ~17ms capture and sub-100ms interaction render times.
* **Text Recognition (Vision Framework):** Integrate Apple's `Vision` framework (`VNRecognizeTextRequest`) for instant, on-device OCR to extract text from captures and facilitate the "Text-Only" blur features.
* **Clipboard & System Drag (NSPasteboard):** The rendered composition must support instantaneous `NSPasteboard` writing and native file dragging directly out of the app window into other macOS applications.

---

## 2. Tool & Feature Matrix

The editor relies on a non-destructive, layer-based system. Every annotation remains editable until the image is explicitly exported or copied.

| # | Tool / Feature | Function | Options / Behavior & Floating Inspector Controls |
| --- | --- | --- | --- |
| 1 | **Copy / Save** | Export composition | Copy to clipboard (`Cmd+C`); Save to file (PNG/JPEG). |
| 2 | **Pin / Window** | Keep floating | Pins the screenshot on screen as a reference window. |
| 3 | **Select / Crop** | Crop/measure | Dimension measurement and canvas re-framing. |
| 4 | **Selection Arrow** | Layer manipulation | Direct selection, translation, and control handle manipulation. |
| 5 | **Speech Bubble** | Text callout | Rounded rectangle with editable multiline text and 1 tail anchor handle. Options: Color, stroke width, fill/transparent mode. |
| 6 | **Plain Text** | Standalone text | Multi-line text. Options: Font size, color, background pill option. |
| 7 | **Rectangle** | Box outlines | 8 boundary handles. Options: Color, stroke width, corner radius (sharp/rounded), fill style (outline, solid, striped). |
| 8 | **Ellipse / Circle** | Circular shapes | 8 boundary handles. Options: Color, stroke width, perfect circle vs freehand/organic ring style. |
| 9 | **Pen (Freehand)** | Vector drawing | Pressure/velocity smoothing. Options: Color, width, cap styles. |
| 10 | **Line** | Straight segments | 2 terminal handles. Options: Color, width, solid/dashed/dotted. |
| 11 | **Arrow** | Curved directional | 3 handles (start, tip, middle quadratic control point). Options: Color, thickness, head style (single, dual, filled). |
| 12 | **Counter Badge** | Step callouts | Auto-increments on click (1, 2, 3...). Rotating pointer handle around a circular badge. Options: Color, size. |
| 13 | **Dimension Line** | Measurement | Draws a line displaying exact pixel distance with tick markers. |
| 14 | **Magnifier** | Zoom lens | Source sampling ring + magnified destination lens linked by a leader line. |
| 15 | **Spotlight** | Highlight regions | Inverted mask darkening everything except active spotlight boxes. Multiple overlapping cutouts combine cleanly. |
| 16 | **Blur / Pixelate** | Obscure info | Rectangular filter layer supporting Gaussian blur or mosaic pixelation. |
| 17 | **Highlighter** | Translucent marker | Semi-transparent color strokes drawn behind or above text content. |
| 18 | **Bezel / Frame** | App framing | Wraps screenshot in a macOS window frame, drop-shadow, or wallpaper. |
| 19 | **Image Overlay** | Secondary images | Insert stickers/images with scale, rotation, and opacity adjustment. |
| 20 | **Color Picker** | Meta info | Displays hex `#000000`, canvas dimensions `WxH px`, and zoom %. |

---

## 3. Micro-Interactions & Modifiers (The "Fiddly Bits")

The application must feel highly responsive. The following keyboard modifiers and contextual behaviors must be implemented:

* **Smart Selection (`A` / `Option`):** When selecting an area, pressing `A` auto-adjusts the crop bounds to snap to visual elements. Holding `Option` (`⌥`) while dragging a selection provides an instant preview of an auto-adjusted bounding box that balances padding perfectly.
* **Mid-Draw Translation (`Space`):** While actively drawing a shape or arrow (mouse down), holding `Space` pauses the sizing logic and translates the entire object across the canvas.
* **Shape Constraints (`Shift`):** Holding `Shift` while dragging a rectangle or ellipse constrains proportions to a perfect square or circle.
* **Advanced Blur & Heal (`Delete`):**
* *Text-Only Blur:* A toggle that uses the Vision framework to identify and obscure only text elements, preserving the surrounding background color.
* *Healing:* Selecting an area and pressing `Delete` triggers a content-aware fill to remove UI objects seamlessly.


* **Precision Measurement (`Arrows` / `Option`):**
* Arrow keys (`↑`, `↓`, `←`, `→`) measure exact vertical or horizontal gaps; a click imprints the measurement layer.
* Holding `Option` measures the outer dimensions of an element.
* Holding `Option+S` or `Option+D` reveals vertical or horizontal snap guides (clicking imprints them).



---

## 4. Elastic Canvas Auto-Sizing

The canvas must behave elastically, expanding dynamically if an annotation is dragged outside the original image boundaries, and contracting when elements are removed.

**Behavioral Rules:**

1. **Infinite Workspace:** Dragging any layer outside the canvas expands the document bounds in real-time.
2. **Strict Padding:** Expanded areas maintain a strict `10px` margin around the outermost bounding box of the furthest element.
3. **Auto-Shrink:** If an out-of-bounds element is deleted or moved inward, the canvas recalculates and shrinks to the next outermost element (plus 10px padding).
4. **Original Integrity:** The canvas bounds will *never* shrink smaller than the exact dimensions of the original background screenshot.
5. **Transparency:** Expanded canvas areas must be transparent (alpha 0) to allow clean PNG exports.

**Computation Algorithm (`computeElasticBounds`):**
Executes continuously during drag events and on layer deletion:

1. Initialize `computedBounds = originalImageBounds`.
2. Iterate through all active layers. Get `layerBounds = layer.getBoundingBox()`.
*Note: `getBoundingBox()` must account for stroke widths, arrow curves, and drop shadows.*
3. If `layerBounds` extends outside `computedBounds`:
* `minX = min(computedBounds.minX, layerBounds.minX - 10.0)`
* `minY = min(computedBounds.minY, layerBounds.minY - 10.0)`
* `maxX = max(computedBounds.maxX, layerBounds.maxX + 10.0)`
* `maxY = max(computedBounds.maxY, layerBounds.maxY + 10.0)`


4. Update the rendering frame to `activeCanvasBounds`. Shift the `CGContext` origin if `minX` or `minY` become negative.

---

## 5. State Management & Swift Data Models (Schema)

To ensure smooth AI generation, here is the defined protocol and struct schema for the layers in Swift.

```swift
import Foundation
import CoreGraphics

// MARK: - Core Protocols
protocol AnnotationLayer {
    var id: UUID { get }
    var type: LayerType { get }
    var zIndex: Int { get set }
    var isVisible: Bool { get set }
    var color: String { get set } // Hex representation
    var strokeWidth: CGFloat { get set }
    
    // Crucial for Elastic Canvas calculating bounds including stroke and tails
    func getBoundingBox() -> CGRect 
}

enum LayerType: String, Codable {
    case arrow, callout, text, rectangle, ellipse, line, pen, counter
    case magnifier, spotlight, blur, guide, backdrop
}

// MARK: - Specific Layer Structs

struct ArrowLayer: AnnotationLayer {
    var id = UUID(); var type: LayerType = .arrow; var zIndex: Int = 0
    var isVisible = true; var color = "#FF0000"; var strokeWidth: CGFloat = 4.0
    
    var start: CGPoint
    var control: CGPoint // Midpoint Bezier curve handle
    var end: CGPoint
    var headType: ArrowHeadType // .standard, .filled, .biDirectional
    
    func getBoundingBox() -> CGRect { /* Bezier calculation + stroke padding */ }
}

struct CalloutLayer: AnnotationLayer {
    // Base properties...
    var frame: CGRect
    var cornerRadius: CGFloat = 8.0
    var text: String
    var fontSize: CGFloat
    var tailTip: CGPoint // Draggable anchor for the bubble's tail
    var isFilled: Bool
    
    func getBoundingBox() -> CGRect { /* Union of frame and tailTip + padding */ }
}

struct CounterLayer: AnnotationLayer {
    // Base properties...
    var center: CGPoint
    var radius: CGFloat
    var value: Int
    var pointerAngle: CGFloat // Radians for the tail position
}

struct FilterLayer: AnnotationLayer {
    // Used for Spotlight & Blur
    // Base properties...
    var rects: [CGRect]
    var filterMode: FilterMode // .gaussian, .pixelate, .spotlight
    var intensity: CGFloat
    var isTextOnlyMode: Bool = false // Vision OCR toggle
}

struct MagnifierLayer: AnnotationLayer {
    // Base properties...
    var sourceCenter: CGPoint
    var targetCenter: CGPoint
    var radius: CGFloat
    var zoomFactor: CGFloat = 2.0
}

```

---

## 6. Rendering Pipeline & Shaders

**Render Order (`CGContext`):**

1. Clear active bounds to `clear` (transparent).
2. Draw `originalImage` bitmap at `(0,0)`.
3. Draw Destructive/Masking Layers (Spotlight & Blur).
4. Sort `AnnotationLayer` array by `zIndex`.
5. Draw Vector Layers (Shapes, Arrows, Text).
6. Draw Active UI (Hover states, 8-point bounding box handles, control anchors).

**Multi-Spotlight Masking Logic:**
Spotlights must never compound (double-darken) where they overlap.

1. Create an offscreen buffer filled with black at `alpha: 0.45`.
2. Set `CGContextSetBlendMode` to `.clear` (or `.destinationOut`).
3. Fill all active spotlight `rects` with `alpha: 1.0` on the buffer (punching holes).
4. Draw the buffer back onto the main context using `.normal` blend mode.

**Real-Time Magnifier Lens Logic:**

1. Sample pixels from the source coordinate: `sourceRect = CGRect(x: sX-R, y: sY-R, w: 2R, h: 2R)`.
2. Apply a circular clip path at the target coordinate.
3. Draw the sampled pixels scaled by `zoomFactor` into the target clip path.
4. Draw the leader line connecting the source and target centers.

---

## 7. Implementation Task Backlog (Prioritized Todo)

### Phase 1: Core Architecture & Rendering

* [ ] **1.1** Scaffold the Swift macOS project using AppKit. Create the floating, borderless `NSPanel` overlay.
* [ ] **1.2** Implement the `CGContext` rendering loop inside a custom `NSView`. Ensure 60fps+ redraws during drag events.
* [ ] **1.3** Implement the base `AnnotationLayer` protocol and specific structs (Arrow, Rectangle, Callout).
* [ ] **1.4** Implement the 3-point Quadratic Bezier math and rendering for the Arrow tool.

### Phase 2: Elastic Canvas Integration

* [ ] **2.1** Abstract `originalImageBounds` and `activeCanvasBounds` in the State Manager.
* [ ] **2.2** Implement precise `getBoundingBox()` math for all vector layers, accounting for stroke width overhangs.
* [ ] **2.3** Build the `computeElasticBounds()` algorithm to dynamically calculate the union rect + `10px` padding.
* [ ] **2.4** Hook the elastic bounds calculation into the mouse drag event handler. Ensure negative `minX`/`minY` coordinates properly translate the `CGContext` origin so the image stays anchored.

### Phase 3: Micro-Interactions & Fiddly Bits

* [ ] **3.1** Implement the `Spacebar` mid-draw translation interrupt.
* [ ] **3.2** Implement the `Shift` constraint for perfect squares/circles.
* [ ] **3.3** Integrate Apple Vision `VNRecognizeTextRequest` and hook it into a smart selection `Option` drag and the `isTextOnlyMode` blur.
* [ ] **3.4** Build the Spotlight offscreen mask buffer to prevent overlap compounding.

### Phase 4: Export & System Integration

* [ ] **4.1** Implement `NSPasteboard` integration to copy the composited `activeCanvasBounds` as a PNG.
* [ ] **4.2** Implement `NSDraggingSource` to allow the user to drag the finished image out of the app into Finder/Messages.
* [ ] **4.3** Hook up the `deleteLayer` event to trigger an auto-shrink bounds recalculation.