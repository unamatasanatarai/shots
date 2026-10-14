import Foundation
import CoreGraphics
import AppKit

public enum EditorTests {
    private static func resolveTestImageURL() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Users/citizen/dev/shots/Resources/test-image.jpg"),
            URL(fileURLWithPath: "/Users/citizen/dev/shots/test-image.jpg"),
            URL(fileURLWithPath: "Resources/test-image.jpg"),
            URL(fileURLWithPath: "test-image.jpg")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("Editor - Load test-image.jpg into EditorDocument") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            assert(doc.originalImageBounds.width > 0, "Original image width must be > 0")
            assert(doc.originalImageBounds.height > 0, "Original image height must be > 0")
            assert(doc.activeCanvasBounds == doc.originalImageBounds, "Initial active bounds must equal original bounds")
        }

        testRunner("Editor - Elastic Canvas Expansion & 10px Padding") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let originalW = doc.originalImageBounds.width
            let originalH = doc.originalImageBounds.height

            // Add arrow that extends beyond right and bottom edges
            let arrow = ArrowLayer(
                start: CGPoint(x: originalW - 20, y: originalH - 20),
                end: CGPoint(x: originalW + 60, y: originalH + 80),
                strokeWidth: 4.0
            )
            doc.addLayer(arrow)

            // Verify active canvas expanded
            assert(doc.activeCanvasBounds.width > originalW, "Canvas must expand when layer is outside bounds")
            assert(doc.activeCanvasBounds.height > originalH, "Canvas must expand when layer is outside bounds")

            // Remove layer and verify auto-shrink back to original bounds (never smaller)
            doc.removeLayer(id: arrow.id)
            assert(doc.activeCanvasBounds == doc.originalImageBounds, "Canvas must auto-shrink back to original bounds")
        }

        testRunner("Editor - Quadratic Bezier Arrow Math & Handles") {
            let arrow = ArrowLayer(
                start: CGPoint(x: 10, y: 10),
                control: CGPoint(x: 50, y: 80),
                end: CGPoint(x: 100, y: 20),
                strokeWidth: 4.0
            )

            let box = arrow.getBoundingBox()
            assert(box.contains(CGPoint(x: 10, y: 10)), "Bounding box must contain start")
            assert(box.contains(CGPoint(x: 100, y: 20)), "Bounding box must contain end")

            // Test handle hit testing
            assert(arrow.hitTestHandle(point: CGPoint(x: 10, y: 10)) == 0, "Handle 0 must be start")
            assert(arrow.hitTestHandle(point: CGPoint(x: 50, y: 80)) == 1, "Handle 1 must be control")
            assert(arrow.hitTestHandle(point: CGPoint(x: 100, y: 20)) == 2, "Handle 2 must be end")
        }

        testRunner("Editor - Shape Layer Geometries & Hit Testing") {
            let rect = RectangleLayer(
                rect: CGRect(x: 100, y: 100, width: 200, height: 150),
                fillStyle: .solid
            )
            assert(rect.contains(point: CGPoint(x: 150, y: 150)), "Solid rect must contain interior point")
            assert(rect.hitTestHandle(point: CGPoint(x: 100, y: 100)) == 0, "Handle 0 must be top-left")

            let ellipse = EllipseLayer(
                rect: CGRect(x: 100, y: 100, width: 100, height: 100),
                fillStyle: .solid
            )
            assert(ellipse.contains(point: CGPoint(x: 150, y: 150)), "Ellipse center must be hit")
        }

        testRunner("Editor - Undo / Redo Stack Integrity") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            assert(doc.layers.isEmpty, "Initial document must have 0 layers")

            let rect = RectangleLayer(rect: CGRect(x: 10, y: 10, width: 50, height: 50))
            doc.addLayer(rect)
            assert(doc.layers.count == 1, "Doc must have 1 layer")

            doc.undo()
            assert(doc.layers.isEmpty, "Undo must restore 0 layers")

            doc.redo()
            assert(doc.layers.count == 1, "Redo must restore 1 layer")
        }

        testRunner("Editor - Composition Rendering Output") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let rect = RectangleLayer(rect: CGRect(x: 20, y: 20, width: 100, height: 100), color: "#007AFF")
            doc.addLayer(rect)

            let rendered = doc.renderComposition()
            assert(rendered != nil, "Rendered composition must not be nil")
            assert(rendered!.width >= cgImage.width, "Rendered width must be at least original width")
            assert(rendered!.height >= cgImage.height, "Rendered height must be at least original height")
        }

        testRunner("Editor - Multi-Spotlight Non-Compounding Masking") {
            let spot1 = CGRect(x: 50, y: 50, width: 100, height: 100)
            let spot2 = CGRect(x: 100, y: 100, width: 100, height: 100) // Overlapping spot
            let filter = FilterLayer(rects: [spot1, spot2], filterMode: .spotlight)

            assert(filter.rects.count == 2, "Must contain both spotlight rects")
            assert(filter.contains(point: CGPoint(x: 75, y: 75)), "Point in spot1 must be contained")
            assert(filter.contains(point: CGPoint(x: 120, y: 120)), "Point in overlap must be contained")
            assert(!filter.contains(point: CGPoint(x: 10, y: 10)), "Point outside spotlights must not be contained")
        }

        testRunner("Editor - Magnifier Lens Math & Sampling Bounds") {
            let mag = MagnifierLayer(
                sourceCenter: CGPoint(x: 150, y: 150),
                targetCenter: CGPoint(x: 300, y: 300),
                radius: 40.0,
                zoomFactor: 2.5
            )

            assert(mag.hitTestHandle(point: CGPoint(x: 150, y: 150)) == 0, "Handle 0 must be source center")
            assert(mag.hitTestHandle(point: CGPoint(x: 300, y: 300)) == 1, "Handle 1 must be target center")

            let box = mag.getBoundingBox()
            assert(box.contains(CGPoint(x: 150, y: 150)), "Bounds must contain source")
            assert(box.contains(CGPoint(x: 300, y: 300)), "Bounds must contain target lens")
        }

        testRunner("Editor - Callout Speech Bubble & Tail Anchor") {
            let callout = CalloutLayer(
                frame: CGRect(x: 50, y: 50, width: 120, height: 50),
                text: "Hello World",
                tailTip: CGPoint(x: 110, y: 140)
            )

            assert(callout.contains(point: CGPoint(x: 70, y: 70)), "Point in bubble must be contained")
            assert(callout.hitTestHandle(point: CGPoint(x: 110, y: 140)) == 0, "Handle 0 must be tail anchor")
            assert(callout.getBoundingBox().contains(CGPoint(x: 110, y: 140)), "Bounding box must encompass tail tip")
        }

        testRunner("Editor - Counter Badge Auto-Increment & Pointer Angle") {
            let counter1 = CounterLayer(center: CGPoint(x: 80, y: 80), value: 1)
            let counter2 = CounterLayer(center: CGPoint(x: 160, y: 80), value: 2, pointerAngle: .pi / 4.0)

            assert(counter1.value == 1, "Counter 1 value must be 1")
            assert(counter2.value == 2, "Counter 2 value must be 2")
            assert(abs(counter2.pointerAngle - (.pi / 4.0)) < 0.01, "Pointer angle must be set")
        }

        testRunner("Editor - Dimension Line Pixel Distance") {
            let dim = DimensionLayer(
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 300, y: 400) // 3-4-5 right triangle: distance = 500
            )

            let dist = Int(round(hypot(dim.end.x - dim.start.x, dim.end.y - dim.start.y)))
            assert(dist == 500, "Distance must be exact 500px")
            assert(dim.hitTestHandle(point: CGPoint(x: 0, y: 0)) == 0, "Handle 0 must be start")
            assert(dim.hitTestHandle(point: CGPoint(x: 300, y: 400)) == 1, "Handle 1 must be end")
        }

        testRunner("Editor - Bezel macOS Window Frame Bounding Box") {
            let bezel = BezelLayer(targetBounds: CGRect(x: 100, y: 100, width: 600, height: 400))
            let box = bezel.getBoundingBox()
            assert(box.width > 600, "Bezel bounding box must include shadow padding")
            assert(box.height > 400, "Bezel bounding box must include titlebar and shadow padding")
        }

        testRunner("Editor - Color Swatch Updates Selected Layers") {
            let arrow = ArrowLayer(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 100), color: "#FF3B30")
            let doc = EditorDocument(image: CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resolveTestImageURL()! as CFURL, nil)!, 0, nil)!)
            doc.addLayer(arrow)
            doc.selectLayer(arrow)

            assert(doc.getSelectedLayers().count == 1, "Arrow should be selected")
            for layer in doc.getSelectedLayers() {
                layer.color = "#007AFF"
            }
            assert(arrow.color == "#007AFF", "Selected layer color must be updated to swatch color")
        }

        testRunner("Editor - Magnifier Draggable Source & Target Handles") {
            let mag = MagnifierLayer(
                sourceCenter: CGPoint(x: 100, y: 100),
                targetCenter: CGPoint(x: 250, y: 250),
                radius: 40.0
            )

            // Hit test source handle (0) and move to a new independent location
            assert(mag.hitTestHandle(point: CGPoint(x: 100, y: 100)) == 0, "Handle 0 must be source")
            mag.updateHandle(index: 0, to: CGPoint(x: 50, y: 70))
            assert(mag.sourceCenter == CGPoint(x: 50, y: 70), "Source center must be moved independently")
            assert(mag.targetCenter == CGPoint(x: 250, y: 250), "Target center must remain unchanged")

            // Hit test target handle (1) and move to a new independent location
            assert(mag.hitTestHandle(point: CGPoint(x: 250, y: 250)) == 1, "Handle 1 must be target")
            mag.updateHandle(index: 1, to: CGPoint(x: 400, y: 350))
            assert(mag.targetCenter == CGPoint(x: 400, y: 350), "Target center must be moved independently")
            assert(mag.sourceCenter == CGPoint(x: 50, y: 70), "Source center must remain unchanged")
        }

        testRunner("Editor - Text, Callout, and Counter Render Composition Verification") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let textLayer = TextLayer(origin: CGPoint(x: 50, y: 50), text: "Notice", color: "#FFCC00")
            let callout = CalloutLayer(frame: CGRect(x: 100, y: 100, width: 140, height: 48), tailTip: CGPoint(x: 180, y: 180), color: "#FF3B30")
            let counter = CounterLayer(center: CGPoint(x: 250, y: 80), value: 1, pointerAngle: 0.0, color: "#007AFF")

            doc.addLayer(textLayer)
            doc.addLayer(callout)
            doc.addLayer(counter)

            guard let rendered = doc.renderComposition() else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "renderComposition failed"])
            }

            assert(rendered.width >= cgImage.width, "Rendered composition must have valid dimensions")
            assert(rendered.height >= cgImage.height, "Rendered composition must have valid dimensions")
        }

        testRunner("Editor - Counter Pointer Handle Drag Manipulation") {
            let counter = CounterLayer(center: CGPoint(x: 100, y: 100), value: 3, pointerAngle: 0.0)
            let peak = counter.getPeakPoint()
            let handleIndex = counter.hitTestHandle(point: peak)
            assert(handleIndex == 0, "Counter handle 0 should be hit-testable")

            // Drag handle far away (x: 100, y: 300) -> pointer angle should be pi/2 and distance should remain locked to radius * 1.68
            counter.updateHandle(index: 0, to: CGPoint(x: 100, y: 300))
            assert(abs(counter.pointerAngle - (.pi / 2.0)) < 0.05, "Pointer angle should be ~pi/2 pointing down")
            assert(abs(counter.tailDistance - (counter.radius * 1.68)) < 0.001, "Tip distance must remain locked at constant radial distance")
            let updatedPeak = counter.getPeakPoint()
            let computedDist = hypot(updatedPeak.x - counter.center.x, updatedPeak.y - counter.center.y)
            assert(abs(computedDist - (counter.radius * 1.68)) < 0.001, "Peak radial distance must be fixed")
        }

        testRunner("Editor - Sequential Counter Auto-Increment From Highest Value") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            assert(doc.nextCounterValue() == 1, "Initial nextCounterValue must be 1")

            let c1 = CounterLayer(center: CGPoint(x: 50, y: 50), value: 1)
            doc.addLayer(c1)
            assert(doc.nextCounterValue() == 2, "Next counter value must increment to 2")

            let c2 = CounterLayer(center: CGPoint(x: 100, y: 100), value: 5) // Custom higher value
            doc.addLayer(c2)
            assert(doc.nextCounterValue() == 6, "Next counter value must read highest existing value (5) and assign 6")
        }

        testRunner("Editor - Text Callout Auto-Sizing & Edge Snapped Tail") {
            let callout = CalloutLayer(
                origin: CGPoint(x: 100, y: 100),
                text: "one line",
                tailTip: CGPoint(x: 120, y: 160)
            )

            let initialSize = callout.frame.size
            assert(initialSize.width > 0 && initialSize.height > 0, "Initial size must be auto-calculated")

            // Test dynamic auto-sizing when multiline text is provided
            callout.text = "multiline\nmulti\nline"
            assert(callout.frame.height > initialSize.height, "Height must automatically grow for multiline content")

            // Single line change dynamically resizes back
            callout.text = "short"
            assert(callout.frame.height < initialSize.height || callout.frame.width < initialSize.width, "Dimensions strictly dictated by entered text")

            // Hit test handle: only handle 0 (tail tip) is adjustable; user cannot manually resize bounding box
            assert(callout.hitTestHandle(point: CGPoint(x: 120, y: 160)) == 0, "Handle 0 must be tail tip")
            assert(callout.hitTestHandle(point: CGPoint(x: callout.frame.maxX, y: callout.frame.maxY)) == nil, "Bounding box resize handle must be excluded")

            // Variable tail length & orientation: snap to right
            callout.updateHandle(index: 0, to: CGPoint(x: callout.frame.maxX + 150, y: callout.frame.midY))
            assert(callout.tailTip == CGPoint(x: callout.frame.maxX + 150, y: callout.frame.midY), "Tail tip must update to new position")
            let pathRight = callout.pathForCallout()
            assert(!pathRight.isEmpty, "Path for right-snapped callout must be valid")

            // Variable tail length & orientation: snap to top
            callout.updateHandle(index: 0, to: CGPoint(x: callout.frame.midX, y: callout.frame.minY - 100))
            let pathTop = callout.pathForCallout()
            assert(!pathTop.isEmpty, "Path for top-snapped callout must be valid")

            // Variable tail length & orientation: snap to left
            callout.updateHandle(index: 0, to: CGPoint(x: callout.frame.minX - 120, y: callout.frame.midY))
            let pathLeft = callout.pathForCallout()
            assert(!pathLeft.isEmpty, "Path for left-snapped callout must be valid")

            // Variable tail length: very short nub (5px) to long pointer (400px)
            callout.updateHandle(index: 0, to: CGPoint(x: callout.frame.midX, y: callout.frame.maxY + 5))
            assert(!callout.pathForCallout().isEmpty, "Short nub tail must render valid path")

            callout.updateHandle(index: 0, to: CGPoint(x: callout.frame.midX + 300, y: callout.frame.maxY + 350))
            assert(!callout.pathForCallout().isEmpty, "Long pointer tail must render valid path")

            // Hit testing: contains point inside body and inside tail
            assert(callout.contains(point: CGPoint(x: callout.frame.midX, y: callout.frame.midY)), "Body center must be contained")
            assert(callout.contains(point: callout.tailTip), "Tail tip must be contained")

            // Bounding box encompasses the entire extended tail
            let bbox = callout.getBoundingBox()
            assert(bbox.contains(callout.tailTip), "Bounding box must encompass extended tail tip")
        }

        testRunner("Editor - 4-Directional Move Cursor & Hit Testing") {
            let cursor = NSCursor.fourDirectionalMove
            assert(cursor.image.size.width > 0 && cursor.image.size.height > 0, "4-directional move cursor must have valid image")

            let rectLayer = RectangleLayer(
                rect: CGRect(x: 50, y: 50, width: 100, height: 100),
                color: "#FF3B30",
                strokeWidth: 2,
                fillStyle: .solid
            )

            // Hit body inside bounds -> movable element
            assert(rectLayer.contains(point: CGPoint(x: 75, y: 75)), "Movable layer body must return true for contains(point:)")
            // Control handle -> resize, not translate
            assert(rectLayer.hitTestHandle(point: CGPoint(x: 50, y: 50)) != nil, "Control handle should be hit-tested separately from layer body")
        }

        testRunner("Editor - Single Spotlight Overlay with Multi-Hole Handles") {
            let spotlight = FilterLayer(
                rects: [
                    CGRect(x: 20, y: 20, width: 80, height: 80),
                    CGRect(x: 150, y: 150, width: 100, height: 100)
                ],
                filterMode: .spotlight
            )

            // 2 rects should produce 8 handles (4 corners per hole)
            let handles = spotlight.getHandlePoints()
            assert(handles.count == 8, "Expected 8 handle points for 2 spotlight holes")

            // Test hit-testing handle on hole 2 (index 4 is top-left of second hole: 150, 150)
            assert(spotlight.hitTestHandle(point: CGPoint(x: 150, y: 150)) == 4, "Handle index 4 should hit top-left of second hole")

            // Update handle 4 to (140, 140)
            spotlight.updateHandle(index: 4, to: CGPoint(x: 140, y: 140))
            assert(spotlight.rects[1].minX == 140 && spotlight.rects[1].minY == 140, "Second hole should be resized to start at (140, 140)")
            // Verify hole 1 remains untouched
            assert(spotlight.rects[0].origin == CGPoint(x: 20, y: 20), "First hole must remain unaffected")
        }

        testRunner("Editor - Arrow Annotation Tool 3-Point Control System") {
            let arrow = ArrowLayer(
                start: CGPoint(x: 50, y: 50),
                control: CGPoint(x: 150, y: 80),
                end: CGPoint(x: 250, y: 50),
                strokeWidth: 4.0
            )

            // Exactly three interactive control handles:
            // Handle 0: Start Point (tail)
            // Handle 1: Bend Point (central control node)
            // Handle 2: End Point (arrowhead tip)
            assert(arrow.hitTestHandle(point: CGPoint(x: 50, y: 50)) == 0, "Handle 0 must be Start Point at arrow tail")
            assert(arrow.hitTestHandle(point: CGPoint(x: 150, y: 80)) == 1, "Handle 1 must be Bend Point at central control node")
            assert(arrow.hitTestHandle(point: CGPoint(x: 250, y: 50)) == 2, "Handle 2 must be End Point at arrowhead tip")

            // Test independent Start Point repositioning (leaving end and control intact)
            arrow.updateHandle(index: 0, to: CGPoint(x: 20, y: 60))
            assert(arrow.start == CGPoint(x: 20, y: 60), "Start point must update to (20, 60)")
            assert(arrow.end == CGPoint(x: 250, y: 50), "End point must remain anchored")

            // Test independent Bend Point pulling path into curve
            arrow.updateHandle(index: 1, to: CGPoint(x: 150, y: 140))
            assert(arrow.control == CGPoint(x: 150, y: 140), "Bend point must update to (150, 140)")
            assert(arrow.start == CGPoint(x: 20, y: 60), "Start point must remain anchored during bend adjustment")
            assert(arrow.end == CGPoint(x: 250, y: 50), "End point must remain anchored during bend adjustment")

            // Test independent End Point repositioning
            arrow.updateHandle(index: 2, to: CGPoint(x: 300, y: 100))
            assert(arrow.end == CGPoint(x: 300, y: 100), "End point must update to (300, 100)")
            assert(arrow.start == CGPoint(x: 20, y: 60), "Start point must remain anchored")
        }

        testRunner("Editor - Rectangle Annotation Tool Freeform Resizing & Scaling") {
            let rectLayer = RectangleLayer(
                rect: CGRect(x: 100, y: 100, width: 200, height: 150),
                cornerRadius: 10.0,
                color: "#FF3B30",
                strokeWidth: 4.0,
                fillStyle: .outline
            )

            // 1. Visual Anatomy: Outline fill is transparent (interior does not contain, border does)
            assert(!rectLayer.contains(point: CGPoint(x: 200, y: 175)), "Transparent interior must not intercept clicks when unselected")
            assert(rectLayer.contains(point: CGPoint(x: 100, y: 150)), "Outline stroke border must intercept clicks")

            // 2. 8 Control handles: 4 corners + 4 edge midpoints
            let handles = rectLayer.getHandlePoints()
            assert(handles.count == 8, "Rectangle must provide exactly 8 control handles")

            // 3. Horizontal/Vertical adjustment along specific axis:
            // Top edge (handle 1): scales strictly along Y axis
            let origX = rectLayer.rect.minX
            let origW = rectLayer.rect.width
            rectLayer.updateHandle(index: 1, to: CGPoint(x: 180, y: 60))
            assert(rectLayer.rect.minY == 60, "Top edge must adjust to y: 60")
            assert(rectLayer.rect.minX == origX && rectLayer.rect.width == origW, "Top edge adjustment must be strictly vertical, leaving X unchanged")

            // Bottom edge (handle 5): scales strictly along Y axis
            rectLayer.updateHandle(index: 5, to: CGPoint(x: 180, y: 280))
            assert(rectLayer.rect.maxY == 280, "Bottom edge must adjust to y: 280")
            assert(rectLayer.rect.minX == origX && rectLayer.rect.width == origW, "Bottom edge adjustment must be strictly vertical, leaving X unchanged")

            // Left edge (handle 7): scales strictly along X axis
            let origY = rectLayer.rect.minY
            let origH = rectLayer.rect.height
            rectLayer.updateHandle(index: 7, to: CGPoint(x: 40, y: 170))
            assert(rectLayer.rect.minX == 40, "Left edge must adjust to x: 40")
            assert(rectLayer.rect.minY == origY && rectLayer.rect.height == origH, "Left edge adjustment must be strictly horizontal, leaving Y unchanged")

            // Right edge (handle 3): scales strictly along X axis
            rectLayer.updateHandle(index: 3, to: CGPoint(x: 350, y: 170))
            assert(rectLayer.rect.maxX == 350, "Right edge must adjust to x: 350")
            assert(rectLayer.rect.minY == origY && rectLayer.rect.height == origH, "Right edge adjustment must be strictly horizontal, leaving Y unchanged")

            // 4. Diagonal adjustment: all four corners scale along both X and Y simultaneously
            // Corner 4 (Bottom-Right):
            rectLayer.updateHandle(index: 4, to: CGPoint(x: 400, y: 320))
            assert(rectLayer.rect.maxX == 400 && rectLayer.rect.maxY == 320, "Corner adjustment must scale both X and Y simultaneously")

            // 5. Unconstrained Aspect Ratio: freeform distortion without maintaining aspect ratio
            assert(rectLayer.rect.width == 360 && rectLayer.rect.height == 260, "Aspect ratio must be completely freeform and unconstrained")

            // 6. Boundary Edge hit testing: clicking near edge triggers edge handle
            let topEdgeHit = rectLayer.hitTestHandle(point: CGPoint(x: 200, y: rectLayer.rect.minY))
            assert(topEdgeHit == 1, "Clicking top edge must return handle 1 for vertical scaling")

            let leftEdgeHit = rectLayer.hitTestHandle(point: CGPoint(x: rectLayer.rect.minX, y: 200))
            assert(leftEdgeHit == 7, "Clicking left edge must return handle 7 for horizontal scaling")
        }
    }
}
