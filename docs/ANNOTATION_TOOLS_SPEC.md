# Impact Annotation Tools Specification

> **Status**: Complete & Verified  
> **Target Version**: Impact 1.0+ / Shots 1.0+  
> **Platform**: macOS 12.0+ (Universal Native AppKit & CoreGraphics)  
> **Zero External Dependencies**

This specification defines the formal mathematical models, interaction algorithms, coordinate spaces, geometry generation, hit-testing matrices, design tokens, and rendering pipelines for all 12 annotation tools in **Impact**. It is designed to be fully reproducible across any implementation.

---

## Table of Contents
1. [Global Architecture & Design Tokens](#1-global-architecture--design-tokens)
2. [Elastic Canvas Engine & Expansion Rules](#2-elastic-canvas-engine--expansion-rules)
3. [Tool 1: Pointer / Select (`V`)](#3-tool-1-pointer--select-v)
4. [Tool 2: Curved Arrow (`A`)](#4-tool-2-curved-arrow-a)
5. [Tool 3: Straight Line (`L`)](#5-tool-3-straight-line-l)
6. [Tool 4: Rectangle (`R`)](#6-tool-4-rectangle-r)
7. [Tool 5: Oval / Ellipse (`O`)](#7-tool-5-oval--ellipse-o)
8. [Tool 6: Spotlight (`S`)](#8-tool-6-spotlight-s)
9. [Tool 7: Step Counter (`C`)](#9-tool-7-step-counter-c)
10. [Tool 8: Callout (`T`)](#10-tool-8-callout-t)
11. [Tool 9: Freehand Pen (`P`)](#11-tool-9-freehand-pen-p)
12. [Tool 10: Highlighter (`H`)](#12-tool-10-highlighter-h)
13. [Tool 11: Privacy Blur (`B`)](#13-tool-11-privacy-blur-b)
14. [Tool 12: Screen Ruler / Dimension (`M`)](#14-tool-12-screen-ruler--dimension-m)
15. [Clipboard Architecture (Copy, Cut, Paste, Duplicate)](#15-clipboard-architecture)
16. [History, State & Undo/Redo Engine](#16-history-state--undoredo-engine)
17. [Verification Assertions & Test Criteria](#17-verification-assertions--test-criteria)

---

## 1. Global Architecture & Design Tokens

### 1.1 Coordinate Space
- **Flipped Coordinate Frame**: Canvas views and bitmap contexts operate in a flipped coordinate system (`isFlipped = true` in AppKit, Y increasing downwards, origin `(0, 0)` at top-left).
- **Physical vs Canvas Coordinates**: All stored geometry vertices $P = (x, y)$ are in unscaled canvas coordinate space relative to the unpadded document origin.
- **Offset Transformation**: When elastic padding expands the canvas origin into negative coordinates, the view offsets all drawing:
  $$\text{canvasX} = \text{viewX} - \text{offsetX}, \quad \text{canvasY} = \text{viewY} - \text{offsetY}$$

### 1.2 Color Swatch Palette
The application enforces an 8-color curated swatch palette:

| Swatch Name | Hex Code | Default Usage | Contrast Rules |
| :--- | :--- | :--- | :--- |
| **Red** (Default) | `#FF3B30` | Arrows, Shapes, Counters, Pen | Primary callout & markup accent |
| **Purple** | `#7048E8` | Markup & Shapes | High-contrast alternative |
| **Yellow** | `#FFCC00` | Highlighter default | Classic document marker tone |
| **Pink** | `#FF2D55` | Markup & Shapes | Vibrant alert color |
| **Teal** | `#00B894` | Markup & Shapes | Soft contrasting tone |
| **Blue** | `#007AFF` | Control handles, Highlight tint | System accent tone |
| **Dark** | `#1E272E` | Monochrome dark | High-key image markup |
| **White** | `#FFFFFF` | Text, handles, light ink | Inverts text color to `#1E272E` on Callouts |

### 1.3 Depth & Drop Shadow Token
All vector annotation layers (Arrows, Rectangles, Ellipses, Counters, Callouts, Lines, Dimensions) apply a uniform natural drop shadow for separation against complex background imagery:
- **Shadow Offset**: `CGSize(width: 0.0, height: -1.0)`
- **Blur Radius**: `2.5 px`
- **Shadow Color**: `rgba(0.0, 0.0, 0.0, 0.25)` (25% black)
- **Text Exemption**: Shadows are cleared before rendering text (Callout text, Counter numbers, Dimension readouts) to preserve crisp sub-pixel glyph legibility.

### 1.4 Universal Hover Outline Token
Unselected solid vector geometries (`CounterLayer`, `ArrowLayer`, `ShapeLayer`) display a soft, reactive glow when the mouse hovers over them:
- **Outer Glow**: Blur radius $5.5\text{ px}$, color `rgba(0.35, 0.70, 1.0, 0.85 * alpha)`.
- **Inner Stroke**: Width $2.0\text{ px}$, color `rgba(0.88, 0.94, 1.0, 0.80 * alpha)`.
- **Animation Timing**: $\Delta\alpha = \pm 0.30$ every $16\text{ ms}$ ($\sim 60\text{ ms}$ fade-in/fade-out). Cleared instantly to $0.0$ on `mouseDown`.

### 1.5 Interactive Control Handles (White Dots)
All resizable layers expose circular control handles matching the universal standard:
- **Geometry**: Solid white `#FFFFFF` circle, radius $r = 4.5\text{ px}$.
- **Border Stroke**: Width $1.5\text{ px}$, color `#007AFF` (macOS System Accent Blue).
- **Hit Detection Radius**: $R_{\text{hit}} = \max(r, 10.0\text{ px}) = 10.0\text{ px}$. A handle captures a touch if $\Delta x^2 + \Delta y^2 \le 100.0$.

### 1.6 Cursor State Matrix
| Tool / Canvas State | Cursor |
| :--- | :--- |
| Empty canvas in Select mode | `NSCursor.arrow` |
| Hovering over layer body (`contains(point) == true`) | Custom 4-directional move cursor (`fourDirectionalMove`) |
| Dragging layer body without handle | Custom 4-directional move cursor (`fourDirectionalMove`) |
| Top/Bottom edge handle hover ($i \in \{1, 5\}$) | `NSCursor.resizeUpDown` |
| Left/Right edge handle hover ($i \in \{3, 7\}$) | `NSCursor.resizeLeftRight` |
| Corner handle hover ($i \in \{0, 2, 4, 6\}$), Arrow handles, or Line handles | `NSCursor.crosshair` |
| Active drawing (Shapes, Pen, Arrow, Line, Blur, Spotlight, Ruler) | `NSCursor.crosshair` |
| Active Callout placement or hover over Callout text editor | `NSCursor.iBeam` |
| Canvas panning (`Right-Click Drag`) | `NSCursor.closedHand` |

---

## 2. Elastic Canvas Engine & Expansion Rules

The canvas dynamically accommodates annotations drawn outside the boundary of the original screenshot without cropping or clipping.

```
┌──────────────────────────────────────────────────────────────┐
│  Elastic Canvas Bounds (expanded)                            │
│                                                              │
│      ┌────────────────────────────────────────┐              │
│      │  Original Image Bounds (min boundary)  │              │
│      │                                        │   ▲          │
│      │                Image                   │   │ Arrow    │
│      │                                        │   │          │
│      └────────────────────────────────────────┘   │          │
│                                                   ●          │
│                                               + 10px padding │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 Dynamic Expansion Equation
1. Initialize bounding box to the original image rectangle:
   $$\text{minX} = \text{orig.minX}, \quad \text{minY} = \text{orig.minY}, \quad \text{maxX} = \text{orig.maxX}, \quad \text{maxY} = \text{orig.maxY}$$
2. For each visible layer $L \in \text{layers}$:
   $$\text{box} = L.\text{getBoundingBox}()$$
   $$\text{minX} = \min(\text{minX}, \, \text{box.minX} - 10.0)$$
   $$\text{minY} = \min(\text{minY}, \, \text{box.minY} - 10.0)$$
   $$\text{maxX} = \max(\text{maxX}, \, \text{box.maxX} + 10.0)$$
   $$\text{maxY} = \max(\text{maxY}, \, \text{box.maxY} + 10.0)$$
3. **Original Integrity Bound**: The canvas **never** shrinks smaller than the original image bounds:
   $$\text{minX} = \min(\text{minX}, \, \text{orig.minX}), \quad \text{minY} = \min(\text{minY}, \, \text{orig.minY})$$
   $$\text{maxX} = \max(\text{maxX}, \, \text{orig.maxX}), \quad \text{maxY} = \max(\text{maxY}, \, \text{orig.maxY})$$
4. **Elastic Contraction**: When external layers are deleted or translated back inside the original frame, the canvas contracts automatically to the minimum bounding hull.

### 2.2 Composition Flattening & Export Pipeline
Exporting or copying to pasteboard executes the following deterministic rendering sequence:
1. `computeElasticBounds()` is evaluated to determine full canvas dimensions $W \times H$.
2. Bitmap context created with `CGColorSpaceCreateDeviceRGB()`, `bitsPerComponent: 8`, `premultipliedLast` alpha.
3. Coordinate transformation applied to map flipped canvas origin $(-\text{minX}, -\text{minY})$ to $(0, 0)$.
4. Original background image drawn at original coordinate offset.
5. **Filter Layer Pass 1**: Gaussian Blur & Pixelate layers are rendered first.
6. **Filter Layer Pass 2**: Spotlight dark mask and punched holes are rendered on top of Blur layers (ensuring blur regions sit under spotlight darkening).
7. **Vector Layer Pass**: Layers sorted ascending by `zIndex` and rendered via native `draw(in:scale:)`.

---

## 3. Tool 1: Pointer / Select (`V`)

The Pointer tool (`.select`, shortcut `V`) is the primary manipulation tool governing selection, hover detection, body translation, and control handle activation.

### 3.1 Precedence & Auto-Switching Rules
1. **Click-to-Select Override**: Clicking on an existing visible layer's handle or body while **any** drawing tool is active immediately selects the layer and auto-switches `document.activeTool` to `.select`.
2. **Empty Canvas Click**: Clicking empty canvas area in `.select` mode deselects all active layers.
3. **Reverse Z-Index Traversal**: Hit-testing evaluates layers from topmost to bottommost.

### 3.2 Translation & Nudge Mechanics
- **Mouse Drag Translation**: Dragging a selected layer's body translates all coordinate anchors uniformly:
  $$P'_k = P_k + (\text{current}.x - \text{last}.x, \, \text{current}.y - \text{last}.y)$$
- **Keyboard 1 pt Nudge**: Pressing Arrow Keys (`←`, `→`, `↑`, `↓`) shifts all selected layers by exactly $1.0\text{ pt}$.
- **Keyboard 10 pt Nudge**: Holding `Shift` with Arrow Keys shifts all selected layers by exactly $10.0\text{ pt}$.
- Single continuous nudge sequences record exactly one undo snapshot upon the initial key stroke.

---

## 4. Tool 2: Curved Arrow (`A`)

The Arrow tool (`.arrow`, shortcut `A`) generates a continuous vector polygon comprising a tapered quadratic Bezier shaft, an equilateral triangular arrowhead, and shape-retaining affine reorientation.

```
       Start Handle (0)
            ● (tail)
             \
              \   Control Handle (1) - Curvature
               \        ●
                \      /
                 \    /
                  \  /
                   ▼
               End Handle (2) - Tip
```

### 4.1 Quadratic Bezier Curve Parameterization
Given start point $P_0$, control point $P_1$, and end tip $P_2$:
$$B(t) = (1 - t)^2 P_0 + 2(1 - t)t P_1 + t^2 P_2, \quad t \in [0, 1]$$

### 4.2 Normalized Invariant Coordinates $(u, v)$
To guarantee that scaling or rotating an arrow preserves its proportional curvature:
$$\vec{D} = P_2 - P_0 = (dx, dy), \quad |\vec{D}|^2 = dx^2 + dy^2$$
- **Axial Ratio ($u$)**:
  $$u = \frac{(P_1.x - P_0.x) dx + (P_1.y - P_0.y) dy}{|\vec{D}|^2}$$
- **Orthogonal Ratio ($v$)**:
  $$v = \frac{(P_1.y - P_0.y) dx - (P_1.x - P_0.x) dy}{|\vec{D}|^2}$$
- Straight arrow default: $u = 0.5, \, v = 0.0$.

### 4.3 Handle Manipulation Rules
When selected, the arrow exposes **3 white circular handles**: Handle 0 ($P_0$), Handle 1 ($P_1$), Handle 2 ($P_2$) with hit radius $8.0\text{ px}$.
- **Dragging Handle 1 (Curvature)**: Directly relocates $P_1 \leftarrow P_{\text{mouse}}$ and recalculates invariant $(u, v)$.
- **Dragging Handles 0 or 2 (Endpoints)**: Moves $P_0$ or $P_2$, dynamically reconstructing $P_1$ to retain curve shape:
  $$P_1.x = P_0.x + u \cdot dx - v \cdot dy$$
  $$P_1.y = P_0.y + u \cdot dy + v \cdot dx$$

### 4.4 Arrowhead & Shaft Geometry
The arrow is rendered as a closed polygon path filled and stroked in a single draw call:
- **Head Length**: $L_{\text{head}} = \min(0.38 \cdot \text{arcLength}, \, L_{\text{target}})$, where $L_{\text{target}} = \min(43 \cdot s, \, 43 \cdot s \cdot (1 - e^{-(\text{arcLength} / 90s)^{0.7}}))$ with $s = \max(0.5, \text{strokeWidth}/4.0)$.
- **Head Width**: Equilateral triangle proportion: $W_{\text{head}} = L_{\text{head}} \times 1.16$.
- **Shaft End Width**: $W_{\text{shaft,end}} = \max(3.0 \cdot s, \, L_{\text{head}} \times 0.38)$.
- **Shaft Tail Taper**: Tapers towards start: $W_{\text{shaft,start}} = W_{\text{shaft,end}} \times \min(0.85, \max(0.53, 0.85 - 0.32 \cdot \min(1.0, \text{arcLength}/350.0)))$.
- **Stroke & Fill**: Fill color matches stroke color; perimeter stroke width $1.8\text{ px}$, line join `.round`, line cap `.round`.

---

## 5. Tool 3: Straight Line (`L`)

The Line tool (`.line`, shortcut `L`) provides straight line segments between two endpoints.

### 5.1 Geometry & Constraints
- **Endpoints**: $P_0$ (start) and $P_1$ (end).
- **Stroke Width**: $4.0\text{ px}$, line cap `.round`.
- **Shift 45° Snapping**: Holding `Shift` snaps angle $\theta = \text{atan2}(dy, dx)$ to increments of $\pi/4$:
  $$\theta_{\text{snapped}} = \text{round}\left(\frac{\theta}{\pi/4}\right) \times \frac{\pi}{4}$$
  $$P_1 = P_0 + |\vec{D}| \cdot (\cos \theta_{\text{snapped}}, \, \sin \theta_{\text{snapped}})$$
- **Minimum Commit Length**: $\text{hypot}(dx, dy) \ge 6.0\text{ px}$.

### 5.2 Control Handles & Manipulation
- Exactly **2 control handles**: Handle 0 ($P_0$) and Handle 1 ($P_1$).
- Dragging Handle 0 updates $P_0$ while $P_1$ remains fixed; dragging Handle 1 updates $P_1$ while $P_0$ remains fixed.
- Dragging the line segment outside handle hit zones translates both endpoints uniformly.

---

## 6. Tool 4: Rectangle (`R`)

The Rectangle tool (`.rectangle`, shortcut `R`) defines rounded rectangular bounding boxes with outline, solid, or striped styling.

### 6.1 Structural Parameters
- **Corner Radius**: $R = 6.0\text{ px}$ (clamped to $\min(R, \frac{\text{width}}{2}, \frac{\text{height}}{2})$).
- **Default Stroke Width**: $4.0\text{ px}$.
- **Fill Styles**:
  - `.outline`: Hollow interior, stroked perimeter.
  - `.solid`: $25\%$ alpha tinted fill + stroked perimeter.
  - `.striped`: $35\%$ alpha diagonal stripes clipped to rect + stroked perimeter.
- **Minimum Dimensions**: Creation requires $w \ge 6.0\text{ px}, \, h \ge 6.0\text{ px}$. Resizing clamps to $w \ge 4.0\text{ px}, \, h \ge 4.0\text{ px}$.

### 6.2 8 Control Handles & Resizing Anchors
When selected, exactly **8 white dot handles** are displayed:
```
  0 (TL) ──────── 1 (TC) ──────── 2 (TR)
    │                               │
  7 (ML)         [Hollow]         3 (MR)
    │                               │
  6 (BL) ──────── 5 (BC) ──────── 4 (BR)
```
- **1D Edge Resizing** ($i \in \{1, 3, 5, 7\}$):
  - Handles 1 & 5 (Top/Bottom): Mutates height against fixed opposite Y anchor; X position and width are pinned.
  - Handles 3 & 7 (Left/Right): Mutates width against fixed opposite X anchor; Y position and height are pinned.
- **2D Corner Resizing** ($i \in \{0, 2, 4, 6\}$):
  - Mutates width and height simultaneously against diagonally opposite corner $(oppX, oppY)$.
- **Handle-Only Resizing Rule**: Dragging along rectangle edges outside the 8 handle hit zones **never** resizes.

### 6.3 Boundary Catchment & Hollow Center
- **Boundary Catchment Width**: $C = \max(10.0, \, \text{strokeWidth} + 6.0)$.
- **Hollow Center**: For outline rectangles, clicks inside $\text{rect.insetBy}(dx: C, dy: C)$ return `contains = false`, passing through to underlying elements or clearing selection. Clicks within the catchment border initiate translation.

---

## 7. Tool 5: Oval / Ellipse (`O`)

The Oval tool (`.ellipse`, shortcut `O`) defines elliptical or circular bounds with 4-axis control handles.

```
                  0: Top-Center
                        ●
                   . ───┴─── .
               .                 .
3: Left-Center ●     [Hollow]    ● 2: Right-Center
               .                 .
                   . ───┬─── .
                        ●
                 1: Bottom-Center
```

### 7.1 Geometry & Constraints
- **Bounding Rect**: Inscribed ellipse inside $CGRect(x, y, w, h)$.
- **Default Stroke Width**: $4.0\text{ px}$, natural drop shadow applied.
- **Fill Styles**: `.outline` (hollow) or `.solid` (25% tint).
- **Shift 1:1 Circle Constraint**: Holding `Shift` during creation or resize locks $w = h = \max(w, h)$.

### 7.2 4 Cardinal Axis Control Handles
The ellipse exposes **4 white circular handles** positioned at the axis extrema:
- **Handle 0 (Top-Center)**: `(midX, minY)` — Vertical resize.
- **Handle 1 (Right-Center)**: `(maxX, midY)` — Horizontal resize.
- **Handle 2 (Bottom-Center)**: `(midX, maxY)` — Vertical resize.
- **Handle 3 (Left-Center)**: `(minX, midY)` — Horizontal resize.
- **Symmetric Circle Resize**: When `isPerfectCircle` is active:
  - Vertical resizing shifts height and adjusts width symmetrically around center X: $\text{minX} = cx - h/2, \, \text{maxX} = cx + h/2$.
  - Horizontal resizing shifts width and adjusts height symmetrically around center Y: $\text{minY} = cy - w/2, \, \text{maxY} = cy + w/2$.

### 7.3 Elliptical Boundary Catchment
- Normalized radial hit formula for point $(x, y)$:
  $$val = \left(\frac{x - cx}{rx}\right)^2 + \left(\frac{y - cy}{ry}\right)^2$$
- For outline ellipses, hit test returns `true` strictly within the catchment band:
  $$val_{\text{outer}} \le 1.0 \quad \text{and} \quad val_{\text{inner}} > 1.0$$
  where $rx_{\text{outer}} = rx + C, \, rx_{\text{inner}} = rx - C$ with $C = \max(10.0, \, \text{strokeWidth} + 6.0)$. Center is non-draggable.

---

## 8. Tool 6: Spotlight (`S`)

The Spotlight tool (`.spotlight`, shortcut `S`) creates a single dark mask overlay with multiple transparent focus windows.

```
┌────────────────────────────────────────────────────────┐
│ Darkened Overlay (Black alpha: 0.50)                   │
│                                                        │
│       ┌─────────────── 1 ───────────────┐              │
│       │ 0                             2 │              │
│       │                                 │              │
│       7       [Punched Clear Hole]      3              │
│       │        (Corner radius: 6px)     │              │
│       │ 6                             4 │              │
│       └─────────────── 5 ───────────────┘              │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### 8.1 Single-Overlay Lifecycle Invariance
1. **Selection Darkening**: Activating `.spotlight` darkens the canvas with a uniform 50% black mask (`rgba(0, 0, 0, 0.50)`).
2. **Single Layer Guarantee**: There is strictly at most **one** spotlight layer in the document. Switching tools and returning reuses the existing overlay without compounding opacity.
3. **Multi-Hole Punching**: Dragging punches rectangular holes using `.clear` blend mode with corner radius $R = 6.0\text{ px}$.
4. **Pruning & Cleanup**: If no holes are created before switching away, the empty overlay is purged. Deleting the last spotlight rectangle removes the overlay completely.

### 8.2 Manipulation Rules (Rectangle Conformance)
- **8 Handles Per Hole**: For $N$ holes, $8N$ control handles exist.
- **Hole-Specific Resizing**: Grabbing a handle resizes only that specific hole; other holes remain stationary.
- **Boundary Catchment Moving**: Moving a hole is achieved by dragging within its $10\text{ px}$ border catchment.
- **Hollow Center**: Clicks inside the punched hole return `contains = false`, allowing underlying content selection.

---

## 9. Tool 7: Step Counter (`C`)

The Step Counter tool (`.counter`, shortcut `C`) drops auto-incrementing numbered badges featuring a directional teardrop pointer tail.

```
                  ┌───────────────┐
                  │ Circular Body │  Radius: 16 px
                  │   ● Number    │  Text: White Bold
                  └───────┬───────┘
                           \
                            \  Teardrop Tail (Default: 135°, Length: r * 1.68)
                             ▼
                             ● Handle 0 (Draggable tip)
```

### 9.1 Geometry & Teardrop Construction
- **Body Radius**: $r = 16.0\text{ px}$.
- **Flank Departure Angle**: $\beta = 0.84\text{ rad} \approx 48^\circ$ from pointer axis.
- **Teardrop Flanks**: Smooth cubic Bezier curves connect the circular body to a rounded tip cap of radius $\max(1.5, r \times 0.055)$.
- **Default Pointer Direction**: $135^\circ$ ($3\pi/4\text{ rad}$, pointing bottom-left in flipped canvas coordinates).
- **Tail Distance**: Locked at $r \times 1.68$.

### 9.2 Number Sequencing & Placement
- **Auto-Increment**: New badges calculate integer value:
  $$\text{value} = \max\Big(\text{counterStep}, \, \max_{L \in \text{counters}}(L.\text{value}) + 1\Big)$$
- **Click Placement**: Clicking at $(x, y)$ pins the **pointer tip** exactly at the clicked coordinate. The circular body is positioned up and to the right along angle $\theta = 135^\circ$.
- **Typography**: Centered bold text in pure white `#FFFFFF` with font size $F = \max(11.0, \, r \times 1.1) = 17.6\text{ px}$.

### 9.3 Handle Manipulation
- **Single Control Handle**: Handle 0 is located at the teardrop tip.
- **Rotational Manipulation**: Dragging Handle 0 updates `pointerAngle = atan2(dy, dx)` around the fixed body center, keeping tail radial length locked at $r \times 1.68$.

---

## 10. Tool 8: Callout (`T`)

The Callout tool (`.callout`, shortcut `T`) generates a vector speech bubble with an integrated, draggable tapered beak. Text is typed in-place and drives bubble dimensions.

```
        ╭──────────────────────╮
        │  Text sets the size  │   Body: bold 16 px text, padding 8 × 12, radius 5
        ╰─────────╮  ╭─────────╯
                   ╲╱
                   ●  Handle 0: beak tip (the only handle)
```

### 10.1 Typography & Layout Engine
- **Font**: System Bold, $16.0\text{ px}$ via shared TextKit 1 layout (`CalloutTextLayout`).
- **Padding**: $8.0\text{ px}$ vertical, $12.0\text{ px}$ horizontal. **Corner Radius**: $R = 5.0\text{ px}$.
- **Line Breaking**: Breaks only at Return (no automatic wrap). Width is determined by the widest line fragment.
- **Minimum Dimensions**: Text width $\ge 14.0\text{ px} \implies$ minimum body width $38.0\text{ px}$ (ensuring beak base fits).
- **Text Color Contrast**: Text is pure white `#FFFFFF`, automatically switching to dark `#1E272E` when placed on the white swatch `#FFFFFF`.

### 10.2 Beak Geometry
- **Edge Snapping**: With $d = P_{\text{tip}} - \text{center}$, beak snaps to horizontal edges if $|d_x| \cdot h > |d_y| \cdot w$, else vertical edges.
- **Base Width**: $\text{base} = \min(\text{flat}, \, \max(16.0, \, 18.0 + 0.2 \cdot \max(0, \, v_{\text{tip}} - 9.0)))$.
- **Fillet Shoulders**: Concave fillets of radius $\min(6.0, \, 0.25 \cdot \text{base})$ seamlessly join the beak to the body.
- **Re-Anchoring**: When text is typed, the body grows away from the beak tip; the beak tip remains locked in place.

### 10.3 In-Place Editing Lifecycle
1. **Creation**: Click pins beak tip; body opens immediately with focused caret in `CalloutTextView`.
2. **Commit Triggers**: ESC, clicking outside the bubble, tool switching, or exporting commits the text.
3. **Empty Removal**: Committing an empty text string prunes the callout without creating an undo step.
4. **Single Undo Step**: The entire text editing session coalesces into exactly one undo snapshot.

---

## 11. Tool 9: Freehand Pen (`P`)

The Freehand Pen tool (`.pen`, shortcut `P`) creates opaque, smooth vector ink curves.

### 11.1 Parameters & Smoothing
- **Stroke Width**: $4.0\text{ px}$, line caps `.round`, line joins `.round`.
- **Blend Mode**: `.normal` at 100% opacity.
- **Sampling Distance Filter**: Successive sampled points enforce $\ge 2.0\text{ px}$ Euclidean distance during drag.
- **Midpoint Quadratic Smoothing**: For strokes with $N \ge 3$ points, quadratic Bezier curves are interpolated through midpoints:
  $$\text{mid}_i = \frac{P_{i-1} + P_i}{2}$$
- **Single-Click Dot**: Clicking without dragging commits a circular ink dot of diameter $4.0\text{ px}$.

### 11.2 Pre-Draw Hover Footprint
When `.pen` is active without mouse down, a reticle indicates the exact ink footprint:
- Outer dark contrast ring ($1.0\text{ px}$), inner white ring ($0.75\text{ px}$), diameter $4.0\text{ px}$.
- Centered precision dot ($1.5 \times 1.5\text{ px}$).

### 11.3 Manipulation
- `hitTestHandle` strictly returns `nil` (freehand strokes cannot be resized).
- Clicking or dragging anywhere on the stroke translates all vertices uniformly.

---

## 12. Tool 10: Highlighter (`H`)

The Highlighter tool (`.highlighter`, shortcut `H`) generates translucent, multiply-blended marker strokes.

### 12.1 Parameters & Color Compositing
- **Stroke Width**: Fixed $20.0\text{ px}$, line caps `.round`, line joins `.round`.
- **Sampling Distance Filter**: Enforces $\ge 2.0\text{ px}$ separation.
- **Compositing Blend Mode**:
  - **Standard Colors**: `CGContext.setBlendMode(.multiply)` with alpha $0.40$.
  - **White / Near-White Swatches** ($r, g, b > 0.90$): Switches to `CGContext.setBlendMode(.normal)` with alpha $0.55$ (preventing invisibility under multiply).

### 12.2 Pre-Draw Hover Footprint
- Diameter $20.0\text{ px}$ circular brush preview.
- 25% color tint fill, outer dark ring $2.0\text{ px}$, inner white ring $1.0\text{ px}$, center crosshair dot.

### 12.3 Manipulation
- Non-resizable (`hitTestHandle` returns `nil`).
- Hit detection threshold: $T = \frac{W}{2} + 4.0 = 14.0\text{ px}$ orthogonal distance to any segment.
- Dragging translates the entire stroke uniformly.

---

## 13. Tool 11: Privacy Blur (`B`)

The Privacy Blur tool (`.blur`, shortcut `B`) applies localized Gaussian blur filters for redaction.

### 13.1 Filter Specification
- **Filter Type**: Gaussian Blur (`CIGaussianBlur`).
- **Default Intensity**: $\sigma = 6.0$.
- **Boundary Clamping**: Filter extent clamped to crop bounds to eliminate transparent fringe artifacts.
- **Stacking Invariant**: Blur layers are strictly composited **under** the Spotlight dark mask.

### 13.2 Interactive Drag Suppression
- **Creation & Drag Highlight**: During creation drag or boundary/handle manipulation, heavy image filtering is deferred. The region displays a frosted translucent preview:
  - Fill: `rgba(0.15, 0.55, 0.95, 0.28)`.
  - Border: `rgba(0.0, 0.48, 1.0, 0.90)`, width $1.5\text{ px}$, corner radius $6.0\text{ px}$.
- **Commit on Release**: Full Gaussian blur re-renders on `mouseUp`.

### 13.3 Handle & Catchment Rules
- Displays **8 white dot handles** identical to the Rectangle tool.
- Boundary catchment $10.0\text{ px}$ enables moving; interior center is hollow and non-draggable.

---

## 14. Tool 12: Screen Ruler / Dimension (`M`)

The Dimension tool (`.dimension`, shortcut `M`) measures pixel distances and draws calibrated dimension lines with a dynamic readout pill.

```
              Tick (14 px)
                  │
  Start Handle 0  ●──────────────────[ 342 px ]──────────────────●  End Handle 1
                  │                                               │
                                                             Tick (14 px)
```

### 14.1 Geometry & Measurement
- **Endpoints**: Start $P_0$, End $P_1$.
- **Stroke**: Width $2.0\text{ px}$, line cap `.round`, color from active palette swatch.
- **Perpendicular Ticks**: Located at $P_0$ and $P_1$, total length $14.0\text{ px}$ ($7.0\text{ px}$ on each side perpendicular to line vector):
  $$\theta = \text{atan2}(dy, dx), \quad \theta_{\text{perp}} = \theta + \pi/2$$
  $$\text{offset} = 7.0 \cdot (\cos \theta_{\text{perp}}, \, \sin \theta_{\text{perp}})$$

### 14.2 Measurement Readout Badge
- **Distance Calculation**: $D = \text{round}\left(\sqrt{\Delta x^2 + \Delta y^2}\right)$.
- **Readout String**: `\(D) px` rendered in `NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)` in pure white.
- **Pill Background**: Centered at midpoint $(P_0 + P_1) / 2$, corner radius $4.0\text{ px}$, horizontal padding $5.0\text{ px}$, vertical padding $2.0\text{ px}$, filled with swatch color at 90% alpha.

### 14.3 Handles & Manipulation
- Exactly **2 white dot handles**: Handle 0 ($P_0$) and Handle 1 ($P_1$).
- Dragging handles relocates endpoints; dragging the line body translates both points uniformly.

---

## 15. Clipboard Architecture

Impact provides an internal vector annotation clipboard with cascading paste offsets:

### 15.1 Operations
- **Copy (`⌘C`)**: Stores deep clones of selected layers to `AnnotationClipboard.shared`. If no layers are selected, flattens composition to PNG and copies to macOS system pasteboard.
- **Cut (`⌘X`)**: Copies selected layers and deletes them from canvas as one undo step.
- **Paste (`⌘V`)**: Inserts clones of clipboard layers offset by $N \times 10\text{ px}$ down and right:
  $$\Delta_N = (N \times 10.0, \, N \times 10.0)$$
- **Duplicate (`⌘D`)**: Clones selected layers in-place offset by $(+10, +10)\text{ px}$ without altering clipboard contents.

### 15.2 Counter Renumbering Across Canvases
When pasting or duplicating `CounterLayer` items, the sequence automatically renumbers to continue following the highest existing counter value on the destination canvas:
$$\text{newValue} = \max_{L \in \text{canvas}}(L.\text{value}) + 1$$

---

## 16. History, State & Undo/Redo Engine

- **Snapshot Storage**: Deep layer clones preserved in undo/redo stacks (maximum 50 snapshots).
- **Stable UUID Invariance**: Cloned layers generated for undo snapshots preserve their stable `UUID`. Cloning for paste/duplicate generates fresh identifiers.
- **Dirty State Tracking**: `isModified` flag tracks layer mutations to prevent redundant duplicate saves on window close.

---

## 17. Verification Assertions & Test Criteria

Any conformant implementation must satisfy the following automated validation assertions:

1. **Freehand Pen Shortcut Invariance**: Hotkey `p` switches to `.pen`; hotkey `d` (without `⌘`) does **not** activate `.pen`.
2. **Privacy Blur Shortcut Invariance**: Hotkey `b` switches to `.blur`; hotkey `u` does **not** activate `.blur`.
3. **Rectangle Hollow Center**: `rect.contains(center) == false`; `rect.contains(edgePoint) == true`.
4. **Ellipse 4-Axis Handles**: Exposes exactly 4 handles; Shift key forces circular aspect ratio.
5. **Arrow Curvature Retention**: Changing length or rotating arrows preserves $(u, v)$ curvature without distortion.
6. **Spotlight Mask Uniqueness**: Document never contains more than 1 spotlight layer; holes punch through with `.clear`.
7. **Counter Sequence Integrity**: Adding new counters automatically selects $\max(\text{existing}) + 1$.
8. **Callout Text Growth**: Callout body scales live with text; beak tip remains pinned.
9. **Elastic Bounds Minimum Floor**: Canvas bounds never contract smaller than original background image.
10. **Layer Stacking Hierarchy**: Blurs render under Spotlight; Spotlight renders under vector annotations.
