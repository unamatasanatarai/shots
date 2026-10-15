# Tool Manipulation & Interaction Specification

This document defines the formal interaction model, geometric algorithms, coordinate systems, hit-testing rules, and state transitions for manipulating annotations in **Impact**: **Pointer (Select)**, **Highlighter**, **Rectangle**, and **Arrow**.

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

## 4. Rectangle Specification

The Rectangle tool (`.rectangle`, shortcut `R`) defines 2D bounding boxes with rounded corners, outline/solid/striped fills, strict handle-only resizing, and hollow boundary dragging.

### 4.1 Structural Constants & Defaults
- **Corner Radius**: $R = 6.0\text{ px}$ (effective radius clamped to $\min(R, \frac{\text{width}}{2}, \frac{\text{height}}{2})$).
- **Default Stroke Width**: $4.0\text{ px}$.
- **Fill Styles**:
  - `.outline`: Hollow center; stroked perimeter.
  - `.solid`: $25\%$ alpha tinted fill + stroked perimeter.
  - `.striped`: $35\%$ alpha diagonal stripes clipped to rect + stroked perimeter.
- **Minimum Valid Creation Dimensions**: $\text{width} \ge 6.0\text{ px} \land \text{height} \ge 6.0\text{ px}$.

### 4.2 Control Handles (White Dots)
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

### 4.3 Resizing Rules (Handle-Only)
- **Edge Perimeter Resizing Forbidden**: Dragging anywhere along the rectangle edges outside the 8 white dot hit zones **never** triggers resizing. Edge clicks strictly initiate translation.
- **1D Edge Handle Resizing** ($i \in \{1, 3, 5, 7\}$):
  - Handles $1, 5$ (Top/Bottom): Modifies height against fixed opposite vertical anchor; X position and width remain pinned.
  - Handles $3, 7$ (Left/Right): Modifies width against fixed opposite horizontal anchor; Y position and height remain pinned.
- **2D Corner Handle Resizing** ($i \in \{0, 2, 4, 6\}$):
  - Modifies both width and height simultaneously using the diagonally opposite corner as the fixed origin $(oppX, oppY)$.
  - Minimum dimension clamp: $\text{width} \ge 4.0\text{ px}, \, \text{height} \ge 4.0\text{ px}$.

### 4.4 Catchment Area & Body Dragging
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

## 5. Arrow Specification

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

## 6. Verification & Test Criteria

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
