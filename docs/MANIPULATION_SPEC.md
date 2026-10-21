# Tool Manipulation & Interaction Specification

This document defines the formal interaction model, geometric algorithms, coordinate systems, hit-testing rules, and state transitions for manipulating annotations in **Impact**: **Pointer (Select)**, **Highlighter**, **Rectangle**, **Arrow**, and **Callout**.

---

## 1. Global Coordinate System & Interaction Conventions

### 1.1 Canvas Space
- All annotation points $P = (x, y)$ exist in canvas coordinate space where $(0, 0)$ corresponds to the unpadded document origin.
- Canvas coordinates account for active canvas offset and padding bounds:
  $$\text{canvasX} = \text{viewX} - \text{offsetX}, \quad \text{canvasY} = \text{viewY} - \text{offsetY}$$

### 1.2 Common Modifier Keys
- **Spacebar (Hold during drag)**: Freezes dimension expansion and translates the layer origin in-flight by $\Delta = (x - x_{\text{prev}}, y - y_{\text{prev}})$.
- **Shift (Hold during drag)**: Constrains aspect ratios or angles (e.g., 1:1 square/circle constraints).
- **Delete / Backspace**: Deletes all currently selected layers and instantly clears hover states.
- **Escape Key (ESC)**: Staged dismissal lifecycle:
  1. *Callout editing ESC*: While a callout's text is being edited (Section 10), ESC only finishes editing. The callout stays selected (or is removed if its text is empty) and the pointer tool (`.select`, shortcut `V`) becomes active. This ESC never deselects and never closes the window.
  2. *First ESC*: If any annotations are selected or a non-pointer tool is active, ESC immediately deselects all layers and returns to the pointer tool.
  3. *Next ESC*: When already on the pointer tool with no active selection or editor, the subsequent ESC closes Impact.
- **Right-Click Drag**: Pans the canvas scroll view with an active `closedHand` cursor.

---

## 2. Pointer (Select Tool) Specification

The Pointer tool (`.select`, shortcut `V`) governs object selection, hover detection, body translation, and control handle activation.

```
                              [mouseDown]
                                   │
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
      [Handle Hit?]                             [Layer Hit?]
        │           │                             │           │
     YES│         NO│                          YES│         NO│
        ▼           ▼                             ▼           ▼
  [Resize Mode]  [Layer Body Hit?]           [Select & Drag] [Clear Selection]
                    │           │
                 YES│         NO│
                    ▼           ▼
             [Select & Drag] [Clear Selection]
```

### 2.1 Tool Precedence & Auto-Switching
1. If the user clicks on an existing visible layer's handle or body while **any** annotation tool is active, the system does **not** draw a new shape. Instead, it:
   - Selects the clicked layer.
   - Automatically switches `document.activeTool` to `.select`.
   - Synchronizes toolbar visuals.
2. Clicking on an empty canvas region when `.select` is active clears all selected layer IDs.

### 2.2 Layer Hit-Testing Order
- Hit-testing traverses the document layers in **reverse display order** (topmost z-index to bottommost).
- The first layer returning `layer.contains(point) == true` or `layer.hitTestHandle(point) != nil` captures the interaction.

### 2.3 Hover Feedback & Translucent Outline
- **Target Layers**: Solid geometries (`CounterLayer`, `ArrowLayer`).
- **Trigger**: When mouse moves over a target layer that is not currently selected.
- **Visuals**:
  - Soft bluish glow: blur radius $5.5\text{ px}$, color `rgba(0.35, 0.70, 1.0, 0.85 * alpha)`.
  - Translucent stroke: width $2.0\text{ px}$, color `rgba(0.88, 0.94, 1.0, 0.80 * alpha)`.
- **Timing**:
  - Fade In: Step $\Delta\alpha = +0.30$ every $16\text{ ms}$ ($\sim 60\text{ ms}$ to $1.0$).
  - Fade Out: Step $\Delta\alpha = -0.30$ every $16\text{ ms}$ ($\sim 60\text{ ms}$ to $0.0$).
  - Instantly cleared to $0.0$ on mouse down or layer deletion.

### 2.4 Cursor State Matrix
| Hover / Drag Condition | Cursor Type |
| :--- | :--- |
| Empty canvas in select mode | `arrow` |
| Hovering over layer body (`contains(point) == true`) | `fourDirectionalMove` |
| Actively dragging a layer body (`activeHandleIndex == nil`) | `fourDirectionalMove` |
| Over Rectangle Top/Bottom edge handles ($i \in \{1, 5\}$) | `resizeUpDown` |
| Over Rectangle Left/Right edge handles ($i \in \{3, 7\}$) | `resizeLeftRight` |
| Over Rectangle Corner handles ($i \in \{0, 2, 4, 6\}$) or Arrow handles | `crosshair` |
| Right-click canvas panning | `closedHand` |

### 2.5 Translation (Moving)
- When dragging a layer body without a handle:
  $$P'_k = P_k + \Delta, \quad \Delta = (\text{curr}.x - \text{last}.x, \, \text{curr}.y - \text{last}.y)$$
- A state snapshot for undo/redo (`document.saveSnapshot()`) is pushed on initial `mouseDown`.
- Elastic document bounds are recomputed on every drag tick.

---

## 3. Highlighter Specification

The Highlighter tool (`.highlighter`, shortcut `H`) provides freehand translucent highlighting with pre-draw targeting.

### 3.1 Core Geometry & Constants
- **Fixed Stroke Width**: $W = 20.0\text{ px}$.
- **Line Caps & Joins**: `.round` caps and `.round` joins.
- **Sampling Distance Filter**: To maintain smooth curves and avoid redundant vertices, a new point $P_{\text{curr}}$ is only appended during `mouseDragged` if:
  $$\text{hypot}(P_{\text{curr}}.x - P_{\text{last}}.x, \, P_{\text{curr}}.y - P_{\text{last}}.y) \ge 2.0\text{ px}$$

### 3.2 Pre-Draw Brush Preview (Hover State)
While `.highlighter` is active and the cursor is within the canvas bounds without holding the mouse button down, an outline preview of the brush footprint is rendered centered at the cursor position:
1. **Brush Circle**: Diameter $20.0\text{ px}$ (radius $r = 10.0\text{ px}$).
2. **Inner Tint**: `color.withAlphaComponent(0.25)`.
3. **Outer Contrast Stroke**: `rgba(0, 0, 0, 0.60)`, line width $2.0\text{ px}$.
4. **Inner Stroke**: `rgba(1, 1, 1, 0.95)`, line width $1.0\text{ px}$.
5. **Center Crosshair Dot**: $2.0 \times 2.0\text{ px}$ solid white dot at $(x - 1, y - 1)$.

### 3.3 Color Blending & Rendering
Highlighter colors blend into the underlying image using specific compositing rules:
- **Standard Colors**:
  - `CGContext.setBlendMode(.multiply)`
  - Alpha: $0.40$
- **White or Near-White Colors** ($r > 0.90 \land g > 0.90 \land b > 0.90$):
  - `.multiply` with white $(1.0, 1.0, 1.0)$ leaves background unchanged (invisible).
  - Therefore, near-white switches to `CGContext.setBlendMode(.normal)` with alpha $0.55$.

### 3.4 Smoothing Equation
For strokes with $N \ge 3$ points, quadratic Bezier segments are constructed between adjacent midpoints:
$$\text{mid}_i = \frac{P_{i-1} + P_i}{2}$$
Segment $i$ curves to $\text{mid}_i$ with control point $P_{i-1}$. The curve terminates with a straight segment to $P_N$. Single-point strokes render as a filled circle of diameter $W$.

### 3.5 Selection & Manipulation Rules
- **No Resizing or Control Handles**: `hitTestHandle(point)` strictly returns `nil`. Highlighter strokes cannot be resized, scaled, or stretched.
- **Hit-Testing (`contains`)**:
  - Distance threshold: $T = \frac{W}{2} + 4.0\text{ px} = 14.0\text{ px}$.
  - Returns `true` if orthogonal projection distance from cursor point $P$ to any segment $[P_i, P_{i+1}]$ is $\le T$.
- **Moving**: Once selected, dragging the highlighter translates all points $P_i \leftarrow P_i + \Delta$.

---

## 4. Freehand Pen Specification

The Freehand Pen tool (`.pen`, shortcut `P`) creates smooth freehand vector ink strokes imitating a real pen, following the same interaction and smoothing rules as the Highlighter tool with an opaque ink profile and small radius.

### 4.1 Core Geometry & Constants
- **Radius & Stroke Width**: Small radius $r = 2.0\text{ px}$ (stroke width $W = 4.0\text{ px}$).
- **Line Caps & Joins**: `.round` caps and `.round` joins.
- **Sampling Distance Filter**: Consecutive sampled points enforce $\ge 2.0\text{ px}$ separation during drag to avoid vertex bloat while retaining high fidelity.

### 4.2 Pre-Draw Pen Tip Preview (Hover State)
While `.pen` is active without holding the mouse button down, an outline preview of the pen nib footprint is rendered centered at the cursor position:
1. **Tip Circle**: Diameter $4.0\text{ px}$ (radius $2.0\text{ px}$).
2. **Inner Tint**: `color.withAlphaComponent(0.25)`.
3. **Contrast Stroke**: Outer dark line $1.0\text{ px}$, inner white line $0.75\text{ px}$.
4. **Precision Center**: $1.5 \times 1.5\text{ px}$ center dot.

### 4.3 Rendering & Single-Point Dots
- **Ink Rendering**: Standard normal blend mode (`.normal`) with 100% opaque color ink.
- **Single-Click Dot**: Clicking without dragging commits a solid circular pen dot with diameter $W = 4.0\text{ px}$.
- **Multi-Point Smoothing**: Strokes with 3+ points construct quadratic Bezier curves through adjacent midpoints.

### 4.4 Non-Scalable Whole-Layer Manipulation
- Calling `hitTestHandle(point)` strictly returns `nil` (suppressing resize handles).
- Clicking or dragging anywhere on the pen stroke translates all points uniformly ($P'_i = P_i + \Delta$).

---

## 5. Rectangle Specification

The Rectangle tool (`.rectangle`, shortcut `R`) defines 2D bounding boxes with rounded corners, outline/solid/striped fills, strict handle-only resizing, and hollow boundary dragging.

### 5.1 Structural Constants & Defaults
- **Corner Radius**: $R = 6.0\text{ px}$ (effective radius clamped to $\min(R, \frac{\text{width}}{2}, \frac{\text{height}}{2})$).
- **Default Stroke Width**: $4.0\text{ px}$.
- **Fill Styles**:
  - `.outline`: Hollow center; stroked perimeter.
  - `.solid`: $25\%$ alpha tinted fill + stroked perimeter.
  - `.striped`: $35\%$ alpha diagonal stripes clipped to rect + stroked perimeter.
- **Minimum Valid Creation Dimensions**: $\text{width} \ge 6.0\text{ px} \land \text{height} \ge 6.0\text{ px}$.

### 5.2 Control Handles (White Dots)
When selected, a rectangle exposes exactly **8 circular white control handles**:

```
  0 (TL) ──────── 1 (TC) ──────── 2 (TR)
    │                               │
  7 (ML)         [Hollow]         3 (MR)
    │                               │
  6 (BL) ──────── 5 (BC) ──────── 4 (BR)
```

- **Coordinates**:
  - $0$: $(x_{\min}, y_{\min})$ [Top-Left]
  - $1$: $(x_{\text{mid}}, y_{\min})$ [Top-Center]
  - $2$: $(x_{\max}, y_{\min})$ [Top-Right]
  - $3$: $(x_{\max}, y_{\text{mid}})$ [Mid-Right]
  - $4$: $(x_{\max}, y_{\max})$ [Bottom-Right]
  - $5$: $(x_{\text{mid}}, y_{\max})$ [Bottom-Center]
  - $6$: $(x_{\min}, y_{\max})$ [Bottom-Left]
  - $7$: $(x_{\min}, y_{\text{mid}})$ [Mid-Left]
- **Handle Appearance**:
  - Solid white circle: radius $r = 4.5\text{ px}$.
  - Blue outline: width $1.5\text{ px}$, color `#007AFF`.
- **Handle Hit-Testing**:
  - Effective hit radius: $R_{\text{hit}} = \max(\text{radius}, 10.0) = 10.0\text{ px}$.
  - Handle $i$ is hit if $\text{hypot}(P.x - P_{i}.x, P.y - P_{i}.y) \le 10.0\text{ px}$.

### 5.3 Resizing Rules (Handle-Only)
- **Edge Perimeter Resizing Forbidden**: Dragging anywhere along the rectangle edges outside the 8 white dot hit zones **never** triggers resizing. Edge clicks strictly initiate translation.
- **1D Edge Handle Resizing** ($i \in \{1, 3, 5, 7\}$):
  - Handles $1, 5$ (Top/Bottom): Modifies height against fixed opposite vertical anchor; X position and width remain pinned.
  - Handles $3, 7$ (Left/Right): Modifies width against fixed opposite horizontal anchor; Y position and height remain pinned.
- **2D Corner Handle Resizing** ($i \in \{0, 2, 4, 6\}$):
  - Modifies both width and height simultaneously using the diagonally opposite corner as the fixed origin $(oppX, oppY)$.
  - Minimum dimension clamp: $\text{width} \ge 4.0\text{ px}, \, \text{height} \ge 4.0\text{ px}$.

### 5.4 Catchment Area & Body Dragging
For outline rectangles, selection and movement are governed by a boundary catchment zone:
- **Catchment Width**:
  $$C = \max(10.0, \, \text{strokeWidth} + 6.0)$$
- **Hit Detection Formula**:
  $$\text{outer} = \text{rect.insetBy}(dx: -C, \, dy: -C)$$
  $$\text{inner} = \text{rect.insetBy}(dx: +C, \, dy: +C)$$
  $$\text{contains}(P) \iff P \in \text{outer} \land P \notin \text{inner}$$
- **Hollow Center Behavior**:
  - Grabbing the center/interior of an outline rectangle returns `false`.
  - Clicks in the center pass through to underlying elements or clear selection.
  - Grabbing within the $10\text{ px}$ catchment along the border initiates moving the entire rectangle.
- **Solid / Striped Rectangles**:
  - `contains(P)` returns `true` across the entire standardized bounding box $\text{rect.standardized}$.

---

## 6. Arrow Specification

The Arrow tool (`.arrow`, shortcut `A`) implements a 3-point quadratic Bezier curve with an auto-aligned arrowhead and shape-retaining affine reorientation.

```
       Start Node (0)
            ●
             \
              \   Control Node (1) - Curvature
               \        ●
                \      /
                 \    /
                  \  /
                   ▼
               End Node (2) - Tip
```

### 5.1 Curve Geometry
A quadratic Bezier curve $B(t)$ with $t \in [0, 1]$ is parameterized by:
- $P_0 = \text{start}$ (tail)
- $P_1 = \text{control}$ (apex of curvature)
- $P_2 = \text{end}$ (arrowhead tip)

$$B(t) = (1 - t)^2 P_0 + 2(1 - t)t P_1 + t^2 P_2$$

### 5.2 Creation Behavior
1. On initial drag start: $P_0 = P_1 = P_2 = P_{\text{start}}$.
2. As the user drags, $P_2 = P_{\text{curr}}$.
3. **Initial Straightness**: During creation, the control point $P_1$ is positioned at the exact collinear midpoint:
   $$P_1 = \left( \frac{P_0.x + P_2.x}{2}, \, \frac{P_0.y + P_2.y}{2} \right)$$
4. Minimum creation length: $\text{hypot}(P_2.x - P_0.x, P_2.y - P_0.y) \ge 10.0\text{ px}$.

### 5.3 Normalized Relative Coordinate System
To preserve curve curvature regardless of scale or rotation, $P_1$ is tracked in normalized local coordinates $(u, v)$ relative to the baseline vector $\vec{D} = P_2 - P_0$:

$$\vec{D} = (dx, dy) = (P_2.x - P_0.x, \, P_2.y - P_0.y), \quad |\vec{D}|^2 = dx^2 + dy^2$$

- **Axial Projection Ratio ($u$)**:
  $$u = \frac{(P_1.x - P_0.x) dx + (P_1.y - P_0.y) dy}{|\vec{D}|^2}$$
- **Orthogonal Offset Ratio ($v$)**:
  $$v = \frac{(P_1.y - P_0.y) dx - (P_1.x - P_0.x) dy}{|\vec{D}|^2}$$
- For a straight arrow, $u = 0.5$ and $v = 0.0$.

### 5.4 Handle Manipulation Rules

When selected, the arrow displays **3 white circular handles**: Handle 0 ($P_0$), Handle 1 ($P_1$), Handle 2 ($P_2$) with hit radius $8.0\text{ px}$.

#### Rule A: Middle Control Node Dragging (Handle 1)
- **Role**: Changes curvature only.
- $P_1$ is set directly to the cursor position $P_{\text{mouse}}$.
- Relative coordinates $(u, v)$ are recalculated and saved.

#### Rule B: Start or End Node Dragging (Handles 0 or 2)
- **Role**: Reorients, resizes, and rotates the arrow while retaining existing curvature shape.
- When dragging Handle 0: $P_0 = P_{\text{mouse}}$.
- When dragging Handle 2: $P_2 = P_{\text{mouse}}$.
- **Shape Retention Equation**: Using the preserved $(u, v)$ ratios and updated vector $\vec{D} = P_2 - P_0$, the control point $P_1$ is dynamically reconstructed:
  $$P_1.x = P_0.x + u \cdot dx - v \cdot dy$$
  $$P_1.y = P_0.y + u \cdot dy + v \cdot dx$$
- *Result*: Shortening, lengthening, or rotating the arrow retains its arc height and relative bend without flattening or distorting.

### 5.5 Arrow Shaft Dragging & Hit-Testing
- **Hit-Testing (`contains`)**:
  - Sample $N = 30$ segments along $B(t)$ for $t \in [0, 1]$.
  - Distance threshold: $T = \max(\text{strokeWidth} \times 1.5, \, 10.0)$.
  - If distance from point $P$ to any segment is $\le T$, return `true`.
- **Moving**:
  - Dragging the arrow shaft outside the 3 handles translates $P_0, P_1, P_2$ by $\Delta$.

---

## 7. Spotlight Tool Specification

The Spotlight tool (`.spotlight`, shortcut `S`) provides a non-compounding dark mask overlay with punched, transparent rectangular highlight holes. It enforces single-overlay lifecycle management and follows all manipulation rules of the rectangle tool.

```
┌────────────────────────────────────────────────────────┐
│ Darkened Overlay (Black alpha: 0.50)                   │
│                                                        │
│       ┌─────────────── 1 ───────────────┐              │
│       │ 0                             2 │              │
│       │                                 │              │
│       7       [Punched Clear Hole]      3              │
│       │                                 │              │
│       │ 6                             4 │              │
│       └─────────────── 5 ───────────────┘              │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### 6.1 Unified Single-Overlay Lifecycle
1. **Selection Darkening**: When the user first selects the Spotlight tool, the entire image is immediately darkened with a uniform $50\%$ black overlay (`CGColor(red: 0, green: 0, blue: 0, alpha: 0.50)`).
2. **Single Overlay Invariance**: There can only ever be **one** spotlight overlay layer in the document at any time. Switching to other tools (Pointer, Arrow, Rectangle, Highlighter) and returning to Spotlight reuses the existing overlay without compounding darkness.
3. **Empty Overlay Clean-up**: If the user switches away from the Spotlight tool before creating any holes, the empty overlay is pruned and normal rendering resumes.
4. **Last Rectangle Removal**: When the user deletes the last spotlight rectangle, the entire spotlight layer is removed and the dark overlay disappears completely.

### 6.2 Multi-Hole Creation
- **Live Hole Preview**: Dragging with the Spotlight tool active interactively punches a real-time rectangular hole into the dark mask using `.clear` blend mode.
- **Corner Curvature**: Each spotlight hole punches rounded corners with radius $R = 6.0\text{ px}$.
- **Unbounded Multiple Holes**: The user can create as many spotlight rectangles as desired; all holes punch through the single underlying dark mask.

### 6.3 Rectangle Tool Rule Conformance
Spotlight rectangles strictly conform to the 4 core manipulation rules of the rectangle tool:
1. **8 White Dot Control Handles Per Hole**:
   - Each hole displays 8 circular white control handles ($r = 4.5\text{ px}$, blue stroke `#007AFF`).
   - For hole $k \in [0, N-1]$, handles are indexed $8k \dots 8k + 7$ (Top-Left, Top-Center, Top-Right, Mid-Right, Bottom-Right, Bottom-Center, Bottom-Left, Mid-Left).
2. **Handle-Only Resizing**:
   - Resizing occurs **only** when grabbing the white dot handles ($10\text{ px}$ hit radius).
   - Side handles (1 and 5) perform 1D vertical resizing against the opposite Y anchor.
   - Side handles (3 and 7) perform 1D horizontal resizing against the opposite X anchor.
   - Corner handles (0, 2, 4, 6) perform 2D freeform resizing against the opposite corner anchor.
   - Grabbing rectangle edges outside the white dots **never** resizes.
3. **Sides + 10px Catchment Area Moving**:
   - Grabbing anywhere along the boundary within a $10\text{ px}$ catchment area initiates moving.
   - Moving translates **only** the grabbed rectangle; all other spotlight holes remain pinned.
4. **Non-Draggable Hollow Center**:
   - The interior / center of the hole returns `contains(point) == false`.
   - Clicks or drags inside the hole center pass through and do not move the rectangle.

---

## 8. Blur Tool Specification

The Blur tool (`.blur`, shortcut `B`) provides localized pixel blurring for privacy and redaction using rectangular selections.

```
┌────────────────────────────────────────────────────────┐
│ Canvas Image                                           │
│       ┌─────────────── 1 ───────────────┐              │
│       │ 0                             2 │              │
│       │                                 │              │
│       7        [Blurred Area]           3              │
│       │   (Translucent during drag)     │              │
│       │ 6                             4 │              │
│       └─────────────── 5 ───────────────┘              │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### 7.1 Drag-Highlight & Blurring Lifecycle
1. **Interactive Creation Dragging**:
   - As the user drags to create a blur region, a frosted translucent preview highlight is displayed:
     - Fill: `rgba(0.15, 0.55, 0.95, 0.28)`.
     - Outline: `rgba(0.0, 0.48, 1.0, 0.90)`, stroke width $1.5\text{ px}$.
     - Corner radius: $R = 6.0\text{ px}$.
   - Heavy filter computation is deferred during creation.
2. **Commit on Release (`mouseUp`)**:
   - When the mouse button is released, the highlight disappears and blurring takes effect over the underlying image content.
3. **Move & Resize Drag Suppression**:
   - When an existing blur rectangle is dragged (either moved via its boundary catchment or resized via its 8 white dot handles), the active blur rendering is temporarily suppressed.
   - The layer reverts in real-time to the frosted translucent highlight rectangle throughout the drag operation.
   - On `mouseUp`, blurring recalculates and re-applies at the new position/dimensions.

### 7.2 Rectangle Tool Rule Conformance
The Blur tool strictly adheres to all standard rectangle manipulation rules:
1. **8 White Dot Control Handles**:
   - Exactly 8 circular white control handles ($r = 4.5\text{ px}$, blue stroke `#007AFF`) positioned at the 4 corners and 4 edge midpoints.
2. **Handle-Only Resizing**:
   - Resizing activates **only** when grabbing the white dot handles ($10\text{ px}$ hit radius).
   - Side handles (1 and 5) perform 1D vertical resizing against the opposite vertical anchor.
   - Side handles (3 and 7) perform 1D horizontal resizing against the opposite horizontal anchor.
   - Corner handles (0, 2, 4, 6) perform 2D freeform resizing against the opposite diagonal anchor.
   - Grabbing edges outside the white dots never resizes.
3. **Sides + 10px Catchment Boundary Moving**:
   - Moving the blur rectangle is enabled strictly by grabbing within a $10\text{ px}$ catchment area around its perimeter.
4. **Hollow Non-Draggable Center**:
   - The interior center of the blur rectangle returns `contains(point) == false`.
   - Grabbing the center never moves the rectangle, allowing interaction with underlying elements if needed.

---

## 9. Line Tool Specification

The Line tool (`.line`, shortcut `L`) provides straight line segments between a start point and an end point.

```
            (Handle 0: Start) ●─────────────────────────● (Handle 1: End)
```

### 8.1 Creation & Geometry
1. **Straight Segment**:
   - Starts at `mouseDown` location $P_0$ and terminates at current drag location $P_1$.
   - Rendered with continuous stroke width $4.0\text{ px}$ and `.round` line caps.
2. **Angle Snapping with Shift**:
   - Holding Shift snaps the line angle to $45^\circ$ increments ($0^\circ, 45^\circ, 90^\circ, 135^\circ$, etc.).
3. **Validation**:
   - Lines must have length $\ge 6.0\text{ px}$ upon `mouseUp` to commit.

### 8.2 Handles & Manipulation Rules
1. **Exactly 2 Control Handles**:
   - Handle 0 ($P_0$): Start point.
   - Handle 1 ($P_1$): End point.
   - Dragging Handle 0 updates $P_0$ while $P_1$ remains anchored.
   - Dragging Handle 1 updates $P_1$ while $P_0$ remains anchored.
   - No intermediary control points or bending.
2. **Body Dragging & Translation**:
   - Dragging anywhere along the line segment within hit-test catchment translates the whole line ($P_0$ and $P_1$) uniformly.
   - Crisp, instant outline on hover without fade.

---

## 10. Callout Tool Specification

The Callout tool (`.callout`, shortcut `T`, toolbar button **Callout [T]** with the `text.bubble` icon, placed right after Counter) creates a filled text box with a single aimable beak. The text is typed in place, and the box size always follows the text.

```
        ╭──────────────────────╮
        │  Text sets the size  │   Body: bold 16 px text, padding 8 × 12, radius 5
        ╰─────────╮  ╭─────────╯
                   ╲╱
                   ●  Handle 0: beak tip (the only handle)
```

### 10.1 Body, Text & Color Constants
- **Font**: system bold, $16\text{ px}$. One TextKit 1 configuration (`CalloutTextLayout`) is shared by measuring, drawing, and the editor, so text never shifts when editing ends.
- **Padding**: $8\text{ px}$ top/bottom, $12\text{ px}$ left/right. **Corner Radius**: $R = 5.0\text{ px}$ (clamped to half the body size).
- **No Wrapping**: Lines break only at Return. Body width is the widest line fragment (trailing spaces included); body height is the laid-out height, including the extra line after a trailing newline.
- **Minimum Size**: Text width $\ge 14\text{ px}$, so the minimum body width is $14 + 24 = 38\text{ px}$ (wide enough for the full default beak). Empty text measures one line tall, so a new callout already has its single-line height.
- **Background**: The active color picker swatch. Recoloring a selected callout recolors its background.
- **Text Color**: Always white, except `#1E272E` on the white swatch (`#FFFFFF`), where white text would vanish.
- **Rendering**: One closed contour (body with the beak spliced into one edge, no seam), filled with a soft shadow (offset $(0, -1)$, blur $2.5$, black $25\%$); text is drawn on top without shadow.

### 10.2 Creation
1. **Press**: With `.callout` active, `mouseDown` pins the beak tip at the press point and places an empty callout centered above it, with a $9\text{ px}$ gap (the default short beak hanging from the bottom edge).
2. **Drag (Optional)**: Dragging before release moves the body with the cursor while the tip stays pinned; the beak re-attaches to the edge facing the tip.
3. **Release**: The callout is appended to the document and an in-place editor opens immediately with a blinking caret (Section 10.4). Creation itself records no undo step; the editing session does.
4. **Cursor**: The I-beam cursor is shown while the Callout tool is active.

### 10.3 Beak Geometry
The beak tip ($P_{\text{tip}}$, handle 0) can sit on any side of the body at any distance.

- **Edge Snapping**: The beak attaches to the edge facing the tip. With $d = P_{\text{tip}} - \text{center}$, it uses the left/right edge if $|d_x| \cdot h > |d_y| \cdot w$, else the top/bottom edge.
- **Edge-Local Frame**: $u$ runs along the edge (clockwise contour), $v$ points outward. Tip depth is clamped to $v_{\text{tip}} \ge 8.0\text{ px}$ (minimum beak length).
- **Fixed Base Width**: The base is independent of the body size:
  $$\text{base} = \min\big(\text{flat},\; \max(16,\; 18 + 0.2 \cdot \max(0,\, v_{\text{tip}} - 9))\big)$$
  The default beak is $18\text{ px}$ wide and $9\text{ px}$ deep. Only dragging the tip further out widens the base ($k = 0.2$ per point of extra length).
- **Corner Exclusion**: The base never touches a rounded corner. Usable flat length is $\text{flat} = \max(4,\, L_{\text{edge}} - 2(R + 2))$, and the base center is clamped to $[R + 2 + \frac{\text{base}}{2},\; L_{\text{edge}} - R - 2 - \frac{\text{base}}{2}]$ while following the tip's $u$.
- **Fillets**: Concave shoulders where the beak meets the body, radius $\min(6,\; 0.25 \cdot \text{base})$, kept off the corner arcs.
- **Taper & Tip**: Cubic sides taper to a round tip cap of radius $1.5\text{ px}$ perpendicular to the beak axis. The side trailing the tip hugs the edge longer (control lead up to $0.22 \times$ the tip offset, capped at the base width), so long tails sweep out of the body; tip-side controls sit $40\%$ along the base-to-tip chords.
- **Re-Anchoring While Typing**: When the text changes, the body grows away from the tip. The beak's edge keeps its outer position and the base center keeps the same fraction along that edge on the same canvas point, so the tip and beak never move (a new callout grows symmetrically above a bottom-center beak).

### 10.4 Editing Session
- **Editor**: A transparent, plain-text `NSTextView` (`CalloutTextView`) sits exactly over the body. While it is open, the layer draws only the bubble, the tip handle is hidden, and the I-beam shows over the body (arrow elsewhere).
- **Live Resizing**: Every keystroke updates the layer text; the body re-measures, re-anchors around the beak, and the editor frame follows. Typing past the image edge grows the elastic canvas and the editor stays aligned.
- **Plain Text Only**: Paste is always plain text. Automatic substitutions, spelling correction, and link detection are off.
- **Selection**: Text can be selected with the mouse or ⌘A. The selection highlight is the text color at $35\%$ alpha; the caret uses the text color.
- **Finishing**: Any of the following ends the session:
  1. ESC.
  2. A click outside the editing callout. The click is consumed: it does not select, drag, or create anything, even on another layer. Clicks on the editing callout's beak are ignored and keep the editor open.
  3. A tool change (toolbar button, overflow menu, or Select button). The chosen tool stays active and nothing is selected.
  4. ⌘C / Save / copy-on-close export and window close: the session is committed first so the export includes the text.
- **On Finish** (cases 1 and 2): Empty text removes the callout. Whitespace-only text (`" "`, `"\n"`) is kept. The tool returns to `.select` and the callout stays selected.

### 10.5 Click Rules on Existing Callouts
- **Double-Click** (`clickCount >= 2`) on any callout body enters editing, with any tool active.
- **Click on the Selected Callout**: A press on the body of the only selected callout becomes a pending edit. If the mouse moves more than $3.0\text{ pt}$ before release, it turns into a normal body drag; otherwise `mouseUp` enters editing. The no-op drag snapshot taken on `mouseDown` is discarded, so the session remains one undo step.
- **Click on an Unselected Callout**: Selects it (and switches to `.select` per Section 2.1). A second click then edits (a slow double-click).
- **Caret Placement**: Re-entering editing places the caret at the clicked character (`characterIndexForInsertion(at:)`). New callouts start with the caret at the end.
- **Tip Handle**: A click within $10\text{ px}$ of the tip always grabs the handle and never edits. Dragging the handle aims the beak; a tip dropped inside the body is pushed $8\text{ px}$ past the nearest edge.
- **Body Drag & Nudge**: Dragging the body (or using arrow keys while selected and not editing) moves the body and the tip together.

### 10.6 Keyboard While Editing
| Key | Behavior |
| :--- | :--- |
| Letters, digits, Delete | Edit the text. Single-letter tool shortcuts and layer deletion are disabled. |
| Return | Inserts a new line (the box grows taller). |
| Tab / Shift-Tab | Swallowed. |
| Arrow keys | Move the caret; the layer is not nudged. |
| ⌘C / ⌘X / ⌘V / ⌘A | Copy, cut, paste as plain text, select all, on the text. |
| ⌘Z | Reverts the whole session (see Section 10.7). |
| ⇧⌘Z | Swallowed (there is nothing to redo inside a session). |
| ⌘= / ⌘− / ⌘0 / ⌘1 / ⌘O | Zoom and Open keep working; the editor stays aligned at every magnification. |
| ESC | Finishes editing (Section 1.2, stage 1). |

### 10.7 Undo Semantics
- **One Step Per Session**: The layers are snapshotted when the session begins (before the new layer is appended, for a new callout). When the session ends with a change, that snapshot is pushed as exactly one undo step. Keystrokes are never individual undo steps.
- **What Counts as a Change**: For a new callout, any non-empty text. For an existing callout, a different text or a different color.
- **No-Op Sessions**: A new callout finished empty, or an existing callout finished unchanged, records no undo step.
- **Recolor During a Session**: Picking a swatch while editing records no separate snapshot; it folds into the session's step.
- **⌘Z While Editing**: Finishes the session and, if it changed anything, undoes it as a whole. A new callout disappears; an existing callout gets its original text and color back and stays selected. An unchanged session is simply closed, so no earlier undo step is touched.
- **After Finishing**: One ⌘Z undoes the whole session (an emptied, removed callout comes back); ⇧⌘Z redoes it.

---

## 11. Verification & Test Criteria

Any conformant implementation must satisfy the following automated validation assertions:

1. **Rectangle Outline Invariance**:
   - `rectLayer.contains(center) == false`
   - `rectLayer.contains(edgePoint) == true`
   - `rectLayer.hitTestHandle(edgePoint) == nil`
   - `rectLayer.hitTestHandle(whiteDotPoint) == handleIndex`
2. **Highlighter Non-Scalability**:
   - `highlighterLayer.hitTestHandle(anyPoint) == nil`
   - `highlighterLayer.contains(pointOnStroke) == true`
   - Translating moves all points without modifying inter-point distances.
3. **Arrow Curvature Retention**:
   - Setting $P_1$ to $(u = 0.5, v = 0.2)$ produces a bent arrow.
   - Moving $P_2$ to double the length of $\vec{D}$ maintains $(u = 0.5, v = 0.2)$.
   - Reconstructed $P_1$ remains at the midpoint along the shaft and scaled orthogonally.
4. **Spotlight Overlay Lifecycle & Rectangle Conformance**:
   - Activating spotlight tool with 0 holes produces a single darkened overlay.
   - $N$ spotlight holes produce exactly $8N$ interactive control handles.
   - Center of spotlight hole returns `contains(point) == false` (hollow / non-draggable).
   - Border of spotlight hole returns `contains(point) == true` (catchment draggable).
   - Deleting holes one by one retains remaining holes in the single overlay.
   - Deleting the last spotlight hole completely removes the overlay (`layers.isEmpty == true`).
5. **Blur Tool Conformance**:
   - Keyboard shortcut `b` selects `.blur` tool.
   - Blur `FilterLayer` exposes 8 handles adhering to 1D and 2D rectangle anchoring.
   - Blur center returns `contains(point) == false` (non-draggable hollow center).
   - Blur boundary returns `contains(point) == true` within 10px catchment.
   - Blurring is suppressed and replaced by translucent highlight preview during creation and moving/resizing drags.
6. **Escape Key Staged Dismissal**:
   - Pressing ESC while editing a callout finishes editing, sets `activeTool = .select`, keeps the callout selected, and keeps the window open.
   - Pressing ESC with an active selection or non-pointer tool deselects all layers, sets `activeTool = .select`, and keeps the window open.
   - Pressing ESC in clean state (pointer tool, 0 selected layers) immediately closes the window.
7. **Callout Model & Beak Geometry**:
   - `textSize("")` is zero-width, `" "` is a few points wide, `"\n"` never reports the unbounded container width, and a trailing newline keeps the widest line's width.
   - `bodyRect` grows and shrinks with the text; the beak tip does not move while the body re-anchors.
   - Tips below, above, left, and right of the body attach the beak to the facing edge; a tip dropped inside the body is pushed outside.
   - `contains` covers the body and the beak and rejects far points; `hitTestHandle(tip) == 0`.
   - `move(by:)` shifts the tip with the body; `clone().id` equals the original's.
   - `textColor` is white, and `#1E272E` on `#FFFFFF`.
8. **Callout Creation & Editing Session**:
   - Keyboard shortcut `t` selects `.callout`; press, drag, release creates one `CalloutLayer` with the tip at the press point and opens a `CalloutTextView` editor.
   - Typing grows the body live; ESC with `"Hi"` keeps the layer selected under `.select` and adds one undo step; ESC with `""` removes it and adds none; `" "` and `"\n"` are kept.
   - An outside click ends editing without selecting or creating another layer; a beak click keeps the editor open.
   - ⌘A then ⌘C puts the text on the general pasteboard; Tab is swallowed; letters type instead of switching tools.
   - Recoloring to `#FFFFFF` while editing switches the editor's text color.
9. **Callout Click Rules & Undo**:
   - First click on an unselected callout selects it; a second click without movement edits; a second click with a $5\text{ px}$ drag moves instead; `clickCount == 2` edits; a tip-handle click never edits.
   - Re-entering editing at the right/left end of `"Hello"` puts the caret at 5 / 0.
   - An edit from `"Hello"` to `"Hi"` is one undo step (`undo()` restores, `redo()` reapplies); emptying an existing callout removes it and `undo()` restores it.
   - ⌘Z while editing removes a new callout, restores an edited one, and never pops an earlier undo step when nothing changed.
   - A tool change, `copyCompositionToClipboard()`, and `close()` during a session each commit it, and the rendered composition contains the text.
10. **Responsive Toolbar With Callout**:
    - The toolbar holds 11 collapsible tools; each width rung collapses exactly one tool, from the end of the list (Ruler, Blur, Highlighter, Pen, then Callout).
    - A collapsed Callout is listed in the overflow menu and remains reachable with `T`.

