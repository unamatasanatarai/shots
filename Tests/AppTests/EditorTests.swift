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
            // Point on the side border (catchment) must be contained for dragging
            assert(filter.contains(point: CGPoint(x: 52, y: 75)), "Point on border of spot1 must be contained")
            // Hollow center of spot1 (75, 75) must NOT be contained for dragging
            assert(!filter.contains(point: CGPoint(x: 75, y: 75)), "Hollow center must not be contained for dragging")
            assert(!filter.contains(point: CGPoint(x: 10, y: 10)), "Point outside spotlights must not be contained")
        }

        testRunner("Editor - Blur Intensity Default Strength & Scope") {
            let blur = FilterLayer(
                rects: [CGRect(x: 50, y: 50, width: 100, height: 100)],
                filterMode: .gaussian
            )
            assert(blur.intensity == 6.0, "Default blur intensity must be calibrated to 6.0")
            assert(blur.type == .blur, "FilterLayer with gaussian mode must report .blur type")
        }

        testRunner("Editor - Reduced Blur Filter Strength Calibration") {
            let blur = FilterLayer(
                rects: [CGRect(x: 50, y: 50, width: 100, height: 100)],
                filterMode: .gaussian,
                intensity: 6.0
            )
            assert(blur.intensity == 6.0, "Blur intensity must reflect calibrated reduced strength of 6.0")
            assert(blur.rects.count == 1, "Blur layer should maintain target rects")
        }

        testRunner("Editor - Counter Badge Auto-Increment & Pointer Angle") {
            let counter1 = CounterLayer(center: CGPoint(x: 80, y: 80), value: 1)
            let counter2 = CounterLayer(center: CGPoint(x: 160, y: 80), value: 2, pointerAngle: .pi / 4.0)

            assert(counter1.value == 1, "Counter 1 value must be 1")
            assert(abs(counter1.pointerAngle - (3.0 * .pi / 4.0)) < 0.01, "Default pointer angle must be 7:30pm (3*pi/4 radians)")
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

        testRunner("Editor - Dead Features Removed from LayerType") {
            let allTypes = LayerType.allCases.map { $0.rawValue }
            assert(!allTypes.contains("Crop"), "LayerType must not contain Crop")
            assert(!allTypes.contains("Plain Text"), "LayerType must not contain Plain Text")
            assert(!allTypes.contains("Magnifier"), "LayerType must not contain Magnifier")
            assert(!allTypes.contains("Bezel / Frame"), "LayerType must not contain Bezel")
            assert(!allTypes.contains("Image Overlay"), "LayerType must not contain Image Overlay")
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

        testRunner("Editor - Overflow Menu Deduplication Against Main Toolbar") {
            let doc = EditorDocument(image: CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resolveTestImageURL()! as CFURL, nil)!, 0, nil)!)
            let canvas = EditorCanvasView(document: doc)
            let toolbar = EditorToolbarView(canvasView: canvas)
            toolbar.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
            toolbar.layout()

            let menu = toolbar.buildOverflowMenu()
            let titles = menu.items.map { $0.title }
            for def in toolbar.collapsibleToolDefinitions {
                assert(!titles.contains(def.title), "Visible tool \(def.title) must NOT be repeated in overflow menu")
            }
        }

        testRunner("Editor - Blur and Counter Render Composition Verification") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let blur = FilterLayer(rects: [CGRect(x: 100, y: 100, width: 140, height: 48)], filterMode: .gaussian, intensity: 6.0)
            let counter = CounterLayer(center: CGPoint(x: 250, y: 80), value: 1, pointerAngle: 0.0, color: "#007AFF")

            doc.addLayer(blur)
            doc.addLayer(counter)

            guard let rendered = doc.renderComposition() else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "renderComposition failed"])
            }

            assert(rendered.width >= cgImage.width, "Rendered composition must have valid dimensions")
            assert(rendered.height >= cgImage.height, "Rendered composition must have valid dimensions")
        }

        testRunner("Editor - Composition Orientation Right-Side Up") {
            let w = 100
            let h = 100
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let imgCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "EditorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
            }

            // Top half RED (y=50..100 in unflipped CGContext), Bottom half GREEN (y=0..50 in unflipped CGContext)
            imgCtx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            imgCtx.fill(CGRect(x: 0, y: 50, width: w, height: 50))
            imgCtx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            imgCtx.fill(CGRect(x: 0, y: 0, width: w, height: 50))

            guard let baseCG = imgCtx.makeImage() else {
                throw NSError(domain: "EditorTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
            }

            let doc = EditorDocument(image: baseCG)
            // Add a blue rectangle at the top: x: 10, y: 15, width: 30, height: 15
            let blueRect = RectangleLayer(rect: CGRect(x: 10, y: 15, width: 30, height: 15), color: "#0000FF", fillStyle: .solid)
            doc.addLayer(blueRect)

            guard let rendered = doc.renderComposition() else {
                throw NSError(domain: "EditorTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "renderComposition failed"])
            }

            let rep = NSBitmapImageRep(cgImage: rendered)
            // Top region (y=5, outside blue rect) must be RED
            let topColor = rep.colorAt(x: 80, y: 5)!
            assert(topColor.redComponent > 0.8 && topColor.greenComponent < 0.3, "Top region must be RED, got red=\(topColor.redComponent) green=\(topColor.greenComponent)")

            // Bottom region (y=80) must be GREEN
            let bottomColor = rep.colorAt(x: 80, y: 80)!
            assert(bottomColor.greenComponent > 0.8 && bottomColor.redComponent < 0.3, "Bottom region must be GREEN, got red=\(bottomColor.redComponent) green=\(bottomColor.greenComponent)")

            // Blue rectangle stroke at (x=25, y=15) must be BLUE
            let blueColor = rep.colorAt(x: 25, y: 15)!
            assert(blueColor.blueComponent > 0.8, "Annotation at top must be BLUE, got blue=\(blueColor.blueComponent)")
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

        testRunner("Editor - Blur Filter Calibration & Multi-Rect Support") {
            let blur = FilterLayer(
                rects: [
                    CGRect(x: 10, y: 10, width: 80, height: 40),
                    CGRect(x: 120, y: 60, width: 90, height: 50)
                ],
                filterMode: .gaussian,
                intensity: 6.0
            )
            assert(blur.intensity == 6.0, "Blur intensity must be 6.0")
            assert(blur.rects.count == 2, "Blur should support multiple redacted rects")
            assert(blur.contains(point: CGPoint(x: 12, y: 12)), "Border point of rect 0 must be contained")
            assert(blur.type == .blur, "FilterLayer must report .blur type")
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

            // 2 rects produce 16 handles (8 per hole: 4 corners + 4 midpoints, following rectangle tool rules)
            let handles = spotlight.getHandlePoints()
            assert(handles.count == 16, "Expected 16 handle points for 2 spotlight holes (8 per hole)")

            // Test hit-testing handle on hole 2 (index 8 is top-left of second hole: 150, 150)
            assert(spotlight.hitTestHandle(point: CGPoint(x: 150, y: 150)) == 8, "Handle index 8 should hit top-left of second hole")

            // Update handle 8 to (140, 140)
            spotlight.updateHandle(index: 8, to: CGPoint(x: 140, y: 140))
            assert(spotlight.rects[1].minX == 140 && spotlight.rects[1].minY == 140, "Second hole should be resized to start at (140, 140)")
            // Verify hole 1 remains untouched
            assert(spotlight.rects[0].origin == CGPoint(x: 20, y: 20), "First hole must remain unaffected")

            // Test independent hole moving
            spotlight.selectedRectIndex = 1
            spotlight.move(by: CGPoint(x: 10, y: 10))
            assert(spotlight.rects[1].minX == 150 && spotlight.rects[1].minY == 150, "Second hole must translate independently")
            assert(spotlight.rects[0].origin == CGPoint(x: 20, y: 20), "First hole must remain unaffected during move")
        }

        testRunner("Editor - Spotlight Overlay Lifecycle (Darkening, Multiple Holes, Removal)") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)

            // 1. When first selecting spotlight tool, entire image gets darkened with overlay effect
            doc.activeTool = .spotlight
            assert(doc.layers.count == 1, "Selecting spotlight must create the unified overlay layer")
            guard let overlay = doc.layers.first as? FilterLayer else {
                fatalError("Expected FilterLayer overlay")
            }
            assert(overlay.filterMode == .spotlight, "Must be spotlight filterMode")
            assert(overlay.rects.isEmpty, "Overlay starts with 0 rects, darkening the entire image")

            // 2. Add first hole
            overlay.rects.append(CGRect(x: 50, y: 50, width: 100, height: 100))
            assert(overlay.rects.count == 1, "First hole added")

            // 3. Switch to another tool and back: there can be only one overlay
            doc.activeTool = .arrow
            assert(doc.layers.count == 1, "Overlay must remain when switching tools with existing holes")
            doc.activeTool = .spotlight
            assert(doc.layers.count == 1, "Only one overlay must exist when switching back to spotlight")

            // 4. Add second hole
            overlay.rects.append(CGRect(x: 200, y: 200, width: 80, height: 80))
            assert(overlay.rects.count == 2, "Second hole added")

            // 5. Remove second hole
            doc.selectedLayerIDs = [overlay.id]
            overlay.selectedRectIndex = 1
            doc.removeSelectedLayers()
            assert(doc.layers.count == 1, "Overlay must remain when removing non-last hole")
            assert(overlay.rects.count == 1, "Only 1 hole should remain")

            // 6. When removing the last spotlight rectangle, the overlay disappears
            doc.selectedLayerIDs = [overlay.id]
            overlay.selectedRectIndex = 0
            doc.removeSelectedLayers()
            assert(doc.layers.isEmpty, "When removing the last spotlight rectangle, the overlay must disappear")
        }

        testRunner("Editor - Blur Tool (Rectangles, 8 Handles, 10px Catchment, Resizing & Moving)") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)

            // 1. Tool activation via 'b' shortcut
            doc.activeTool = .blur
            assert(doc.activeTool == .blur, "Active tool must be .blur")

            // 2. Blur FilterLayer initialized with Gaussian mode and rectangular geometry
            let blurLayer = FilterLayer(
                rects: [CGRect(x: 100, y: 100, width: 200, height: 120)],
                filterMode: .gaussian,
                intensity: 16.0,
                selectedRectIndex: 0
            )
            doc.addLayer(blurLayer)
            doc.selectLayer(blurLayer)

            // 3. Exactly 8 white dot control handles (conforming to rectangle tool rules)
            let handles = blurLayer.getHandlePoints()
            assert(handles.count == 8, "Blur rectangle must have exactly 8 control handles, got: \(handles.count)")
            assert(handles[0] == CGPoint(x: 100, y: 100), "Handle 0 must be Top-Left")
            assert(handles[1] == CGPoint(x: 200, y: 100), "Handle 1 must be Top-Center")
            assert(handles[2] == CGPoint(x: 300, y: 100), "Handle 2 must be Top-Right")
            assert(handles[3] == CGPoint(x: 300, y: 160), "Handle 3 must be Mid-Right")
            assert(handles[4] == CGPoint(x: 300, y: 220), "Handle 4 must be Bottom-Right")
            assert(handles[5] == CGPoint(x: 200, y: 220), "Handle 5 must be Bottom-Center")
            assert(handles[6] == CGPoint(x: 100, y: 220), "Handle 6 must be Bottom-Left")
            assert(handles[7] == CGPoint(x: 100, y: 160), "Handle 7 must be Mid-Left")

            // 4. Handle hit testing on white dots
            assert(blurLayer.hitTestHandle(point: CGPoint(x: 100, y: 100)) == 0, "Top-Left handle hit")
            assert(blurLayer.hitTestHandle(point: CGPoint(x: 200, y: 100)) == 1, "Top-Center handle hit")
            assert(blurLayer.hitTestHandle(point: CGPoint(x: 300, y: 220)) == 4, "Bottom-Right handle hit")

            // 5. Non-draggable center (hollow): center must return false
            let centerPoint = CGPoint(x: 200, y: 160)
            assert(!blurLayer.contains(point: centerPoint), "Center of blur rectangle must NOT be draggable (hollow)")

            // 6. 10px catchment boundary: grabbing sides returns true
            let edgePoint = CGPoint(x: 100, y: 140)
            assert(blurLayer.contains(point: edgePoint), "Boundary edge within 10px catchment must be draggable")

            // 7. 1D side handle resizing (Top-Center handle 1)
            blurLayer.updateHandle(index: 1, to: CGPoint(x: 200, y: 80))
            assert(blurLayer.rects[0].minY == 80, "Top edge should resize to y=80")
            assert(blurLayer.rects[0].maxY == 220, "Bottom edge must remain anchored at y=220")

            // 8. Translation via move(by:)
            blurLayer.move(by: CGPoint(x: 15, y: 20))
            assert(blurLayer.rects[0].origin.x == 115, "Rect X translated by +15")
            assert(blurLayer.rects[0].origin.y == 100, "Rect Y translated by +20")

            // 9. Filter rendering into context takes effect
            let testCtx = CGContext(
                data: nil,
                width: 400,
                height: 400,
                bitsPerComponent: 8,
                bytesPerRow: 1600,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            blurLayer.applyFilter(to: cgImage, canvasBounds: CGRect(x: 0, y: 0, width: 400, height: 400), in: testCtx)
        }

        testRunner("Editor - Escape Key Two-Stage Lifecycle (Deselect / Tool Reset, then Window Close)") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)
            let canvas = EditorCanvasView(document: doc)

            var closeCount = 0
            canvas.onCloseRequested = {
                closeCount += 1
            }

            // Scenario 1: Rectangle selected + Blur tool active
            doc.activeTool = .blur
            let rect = RectangleLayer(rect: CGRect(x: 10, y: 10, width: 50, height: 50))
            doc.addLayer(rect)
            doc.selectLayer(rect)

            assert(!doc.selectedLayerIDs.isEmpty, "Layer must be initially selected")
            assert(doc.activeTool == .blur, "Tool must be .blur")

            // First ESC: Deselects and returns to pointer tool (V)
            canvas.handleEscapeKey()
            assert(doc.selectedLayerIDs.isEmpty, "First ESC must DESELECT all layers")
            assert(doc.activeTool == .select, "First ESC must return to pointer tool (.select)")
            assert(closeCount == 0, "First ESC must not close Impact")

            // Next ESC: Nothing selected + already on pointer tool -> Closes Impact
            canvas.handleEscapeKey()
            assert(closeCount == 1, "Next ESC must close Impact")

            // Scenario 2: Arrow tool active, nothing selected
            closeCount = 0
            doc.activeTool = .arrow
            assert(doc.selectedLayerIDs.isEmpty, "No selection")
            assert(doc.activeTool == .arrow, "Active tool is arrow")

            // First ESC: Returns to pointer tool (.select)
            canvas.handleEscapeKey()
            assert(doc.activeTool == .select, "First ESC must return to pointer tool")
            assert(closeCount == 0, "First ESC must not close Impact")

            // Next ESC: Closes Impact
            canvas.handleEscapeKey()
            assert(closeCount == 1, "Next ESC must close Impact")
        }

        testRunner("Editor - Copy to Clipboard on Window Close Preference") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)
            let rect = RectangleLayer(rect: CGRect(x: 20, y: 20, width: 60, height: 60), color: "#007AFF")
            doc.addLayer(rect)

            let panel = EditorPanel(document: doc)

            // Test 1: Enabled -> Closing panel copies image with annotations to general pasteboard
            EditorPanel.copyToClipboardOverride = true
            NSPasteboard.general.clearContents()

            panel.close()

            let pasteboard = NSPasteboard.general
            assert(pasteboard.data(forType: .png) != nil, "Closing panel must copy PNG composition to pasteboard when preference is enabled")
            assert(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil), "Pasteboard must contain readable NSImage object")

            // Test 2: Disabled -> Closing panel does NOT copy to pasteboard
            let doc2 = EditorDocument(image: cgImage)
            let panel2 = EditorPanel(document: doc2)
            EditorPanel.copyToClipboardOverride = false
            NSPasteboard.general.clearContents()

            panel2.close()

            assert(NSPasteboard.general.data(forType: .png) == nil, "Closing panel must NOT copy to pasteboard when preference is disabled")

            // Clean up override
            EditorPanel.copyToClipboardOverride = nil
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

            // Test End Point repositioning: reorients and scales while retaining curve shape
            let origRelU = arrow.relativeControl.u
            let origRelV = arrow.relativeControl.v
            arrow.updateHandle(index: 2, to: CGPoint(x: 300, y: 100))
            assert(arrow.end == CGPoint(x: 300, y: 100), "End point must update to (300, 100)")
            assert(arrow.start == CGPoint(x: 20, y: 60), "Start point must remain anchored")
            assert(abs(arrow.relativeControl.u - origRelU) < 0.001, "Relative control U must remain fixed to retain shape")
            assert(abs(arrow.relativeControl.v - origRelV) < 0.001, "Relative control V must remain fixed to retain shape")
        }

        testRunner("Editor - Rectangle Annotation Tool Freeform Resizing & Scaling") {
            let rectLayer = RectangleLayer(
                rect: CGRect(x: 100, y: 100, width: 200, height: 150),
                cornerRadius: 10.0,
                color: "#FF3B30",
                strokeWidth: 4.0,
                fillStyle: .outline
            )

            // 1. Visual Anatomy: Outline rectangle moves by dragging sides + 10px catchment area; center is non-draggable
            assert(!rectLayer.contains(point: CGPoint(x: 200, y: 175)), "Rectangle center must not intercept clicks for dragging")
            assert(rectLayer.contains(point: CGPoint(x: 100, y: 150)), "Sides with 10px catchment area must intercept clicks for moving")
            assert(rectLayer.hitTestHandle(point: CGPoint(x: 100, y: 150)) == nil, "Arbitrary points on sides must not be resize handles")
            assert(rectLayer.hitTestHandle(point: CGPoint(x: 100, y: 100)) == 0, "White dot handle must be resize handle")

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

            // 6. Resize only by grabbing the white dots: arbitrary points on edge do not trigger resize handles
            let topEdgePoint = CGPoint(x: 120, y: rectLayer.rect.minY)
            assert(rectLayer.hitTestHandle(point: topEdgePoint) == nil, "Arbitrary point along top edge must not trigger resize")
            assert(rectLayer.contains(point: topEdgePoint), "Arbitrary point along top edge must trigger move via contains(point:)")

            let topCenterDot = CGPoint(x: rectLayer.rect.midX, y: rectLayer.rect.minY)
            assert(rectLayer.hitTestHandle(point: topCenterDot) == 1, "Clicking white dot handle 1 must return handle 1 for vertical scaling")
        }

        testRunner("Editor - Line Annotation Tool Straight Segments & 2-Point Controls") {
            let line = LineLayer(
                start: CGPoint(x: 50, y: 50),
                end: CGPoint(x: 250, y: 150),
                color: "#FF3B30",
                strokeWidth: 4.0,
                lineStyle: .solid
            )

            // 1. Visual Anatomy & Styling
            assert(line.color == "#FF3B30", "Line stroke color must be solid red")
            assert(line.strokeWidth == 4.0, "Line stroke width must be uniform 4.0")
            assert(line.lineStyle == .solid, "Line style must be continuous solid line")

            // 2. Exactly two interactive control points (start: 0, end: 1)
            assert(line.hitTestHandle(point: CGPoint(x: 50, y: 50)) == 0, "Handle 0 must be origin point")
            assert(line.hitTestHandle(point: CGPoint(x: 250, y: 150)) == 1, "Handle 1 must be terminus point")
            // No intermediary bend points or midpoint handles
            assert(line.hitTestHandle(point: CGPoint(x: 150, y: 100)) == nil, "No intermediary bend points or curve handles permitted")

            // 3. Dynamic adjustment of origin: reorients angle & length while terminus remains anchored
            line.updateHandle(index: 0, to: CGPoint(x: 30, y: 80))
            assert(line.start == CGPoint(x: 30, y: 80), "Origin point must update to (30, 80)")
            assert(line.end == CGPoint(x: 250, y: 150), "Terminus must remain anchored when moving origin")

            // 4. Dynamic adjustment of terminus: reorients angle & length while origin remains anchored
            line.updateHandle(index: 1, to: CGPoint(x: 300, y: 80))
            assert(line.end == CGPoint(x: 300, y: 80), "Terminus point must update to (300, 80)")
            assert(line.start == CGPoint(x: 30, y: 80), "Origin must remain anchored when moving terminus")

            // 5. Line body hit testing and translation
            let midPoint = CGPoint(x: (line.start.x + line.end.x) / 2.0, y: (line.start.y + line.end.y) / 2.0)
            assert(line.contains(point: midPoint), "Line body must return true for contains(point:) for translation")
            assert(!line.contains(point: CGPoint(x: midPoint.x, y: midPoint.y + 40)), "Point far away must not be contained")

            // Whole line translation
            line.move(by: CGPoint(x: 10, y: 20))
            assert(line.start == CGPoint(x: 40, y: 100) && line.end == CGPoint(x: 310, y: 100), "Move must translate entire line uniformly")

            // 6. Canvas interactive creation & Hotkey 'L'
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let canvasDoc = EditorDocument(image: cgImage)
            let panel = EditorPanel(document: canvasDoc)
            let canvas = panel.canvasView

            // Hotkey 'l' sets activeTool = .line
            let keyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
            canvas.keyDown(with: keyEvent)
            assert(canvasDoc.activeTool == .line, "Hotkey 'l' must switch activeTool to .line")

            // Simulate mouse down, drag, and mouse up to draw straight line from (10, 10) to (100, 50)
            let downEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDown(with: downEvent)

            let dragEvent = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 100, y: 50), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDragged(with: dragEvent)

            let upEvent = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 100, y: 50), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0)!
            canvas.mouseUp(with: upEvent)

            assert(canvasDoc.layers.count == 1, "MouseUp must commit created LineLayer to document layers")
            guard let createdLine = canvasDoc.layers.first as? LineLayer else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Committed layer must be LineLayer"])
            }
            assert(abs(createdLine.end.x - createdLine.start.x - 90.0) < 0.001, "Line delta X must match drag delta")
            assert(canvasDoc.selectedLayerIDs.contains(createdLine.id), "Created line must be automatically selected")
        }

        testRunner("Editor - Window Deactivation, Cmd-Tab & Scale-To-Fit") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let panel = EditorPanel(document: doc)

            // 1. Window must NOT hide on deactivate (clicking away does not close it)
            assert(!panel.hidesOnDeactivate, "EditorPanel hidesOnDeactivate must be false so clicking away does not close/hide it")

            // 2. Cmd-Tab window collection behavior
            assert(panel.collectionBehavior.contains(.participatesInCycle), "EditorPanel must participate in window cycle")
            assert(panel.collectionBehavior.contains(.managed), "EditorPanel must be managed for standard window switching")
            assert(panel.level == .normal, "EditorPanel initial level must be .normal for standard window ordering")

            // 3. Window Sizing: minimum width is responsive (allows narrow resizing down to <= 320), default height 400
            assert(panel.minSize.width <= 320.0, "EditorPanel minSize.width must allow responsive compact resizing (<= 320.0)")
            assert(panel.minSize.height <= 400.0, "EditorPanel minSize.height must be <= 400.0")

            // Verify window does not block resizing down to 300pt
            panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 300), display: true)
            assert(panel.frame.width == 300.0, "EditorPanel must allow resizing down to 300pt without toolbar blocking it")
            assert(panel.contentView?.fittingSize.width ?? 0 <= 320.0, "ContentView fitting size must not force wide window")

            // 4. Large image best-fit scaling
            panel.scaleToFit()
            if let sv = panel.scrollView {
                assert(sv.allowsMagnification, "NSScrollView allowsMagnification must be true")
                assert(sv.magnification > 0.0 && sv.magnification <= 1.0, "Scale to fit must compute a positive scale <= 1.0")
                assert(sv.contentView is CenteringClipView, "ScrollView clipView must be CenteringClipView")

                // Test Zoom In / Zoom Out methods
                let initialMag = sv.magnification
                panel.zoomIn()
                assert(sv.magnification > initialMag, "Zoom in must increase magnification")
                panel.zoomOut()
                assert(abs(sv.magnification - initialMag) < 0.01, "Zoom out must decrease magnification back")
            }

            // 5. Small image: if image is smaller than viewport, center at 100% (1.0) scale
            let smallContext = CGContext(
                data: nil,
                width: 100,
                height: 80,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let smallImage = smallContext.makeImage()!
            let smallDoc = EditorDocument(image: smallImage)
            let smallPanel = EditorPanel(document: smallDoc)
            smallPanel.scaleToFit()
            if let smallSV = smallPanel.scrollView {
                assert(smallSV.magnification == 1.0, "Smaller image must scale to 100% (1.0) and be centered")
            }
        }

        testRunner("Editor - Direct Numbered Save (e.g. arero.jpg -> arero-2.jpg)") {
            let context = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let img = context.makeImage()!
            let doc = EditorDocument(image: img)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("arero.jpg")
            let originalBytes = Data([0x01, 0x02, 0x03, 0x04])
            try? originalBytes.write(to: sourceFile)
            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("arero-2.jpg"))
                try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("arero-3.jpg"))
            }

            let panel = EditorPanel(document: doc, title: "arero.jpg", sourceFileURL: sourceFile)
            let nextURL = panel.nextAvailableFileURL()
            assert(nextURL.lastPathComponent == "arero-2.jpg", "Next file must be arero-2.jpg, got: \(nextURL.lastPathComponent)")

            // Test close: upon closing Impact, always save to file as originalfilename-2.extension-original without overwriting original
            panel.close()

            let savedFile2 = tempDir.appendingPathComponent("arero-2.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile2.path), "Closing panel must automatically save to arero-2.jpg")

            // Verify original file was not overwritten
            let readOriginal = try? Data(contentsOf: sourceFile)
            assert(readOriginal == originalBytes, "Original file arero.jpg must NEVER be overwritten")

            // Next session: closing a new panel increments to arero-3.jpg without overwriting arero-2.jpg or arero.jpg
            let doc2 = EditorDocument(image: img)
            let panel2 = EditorPanel(document: doc2, title: "arero.jpg", sourceFileURL: sourceFile)
            panel2.close()

            let savedFile3 = tempDir.appendingPathComponent("arero-3.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile3.path), "Subsequent close must save to next numbered file arero-3.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile2.path), "arero-2.jpg must remain intact")
        }

        testRunner("Editor - Freehand Pen Tool (Shortcut P, Brush Preview, Smooth Curves, Non-Scalable Whole Move)") {
            // 1. Layer Geometry & Highlighter Rule Conformance
            let pen = PenLayer(
                points: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40), CGPoint(x: 80, y: 30)],
                color: "#007AFF",
                strokeWidth: 4.0
            )

            // Radius is 2.0 (strokeWidth 4.0)
            assert(pen.strokeWidth == 4.0, "Pen stroke width must default to 4.0 (radius 2.0)")

            // Non-scalable: hitTestHandle must strictly return nil
            assert(pen.hitTestHandle(point: CGPoint(x: 20, y: 20)) == nil, "Pen must not expose scalable control handles")
            assert(pen.hitTestHandle(point: CGPoint(x: 80, y: 30)) == nil, "Pen must not expose scalable control handles")

            // Whole layer translation
            assert(pen.contains(point: CGPoint(x: 20, y: 20)), "Point on stroke must return contains == true")
            pen.move(by: CGPoint(x: 10, y: 5))
            assert(pen.points[0] == CGPoint(x: 30, y: 25), "Moving pen layer must translate all vertices uniformly")

            // Single click dot support
            let dotPen = PenLayer(points: [CGPoint(x: 50, y: 50)], color: "#FF3B30", strokeWidth: 4.0)
            assert(dotPen.contains(point: CGPoint(x: 50, y: 50)), "Single dot pen must return contains == true")

            // 2. Canvas & Hotkey Interaction
            let context = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)
            let canvas = panel.canvasView

            // Hotkey 'p' switches to .pen
            let keyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35)!
            canvas.keyDown(with: keyEvent)
            assert(doc.activeTool == .pen, "Hotkey 'p' must switch activeTool to .pen")

            // Draw freehand stroke: down at (10, 10), drag to (30, 20) and (50, 40), up at (50, 40)
            let downEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDown(with: downEvent)

            let dragEvent1 = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 30, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDragged(with: dragEvent1)

            let dragEvent2 = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 50, y: 40), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDragged(with: dragEvent2)

            let upEvent = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 50, y: 40), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0)!
            canvas.mouseUp(with: upEvent)

            assert(doc.layers.count == 1, "Pen drawing must commit a PenLayer to document layers")
            guard let createdPen = doc.layers.first as? PenLayer else {
                throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Created layer must be PenLayer"])
            }
            assert(createdPen.points.count >= 2, "Pen layer must contain sampled points")
            assert(doc.selectedLayerIDs.contains(createdPen.id), "Created pen layer must be automatically selected")

            // Composition rendering must render the pen layer without failure
            let rendered = doc.renderComposition()
            assert(rendered != nil, "renderComposition with pen layer must succeed")
        }

        testRunner("Editor - Universal Hover Outline on All Annotation Elements") {
            let context = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let canvas = EditorCanvasView(document: doc)

            let rectLayer = RectangleLayer(rect: CGRect(x: 10, y: 10, width: 60, height: 40))
            let ellipseLayer = EllipseLayer(rect: CGRect(x: 80, y: 10, width: 50, height: 50))
            let arrowLayer = ArrowLayer(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 40, y: 40))
            let counterLayer = CounterLayer(center: CGPoint(x: 100, y: 100), value: 1)
            let lineLayer = LineLayer(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 50, y: 10))
            let penLayer = PenLayer(points: [CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 15)])
            let highlighterLayer = HighlighterLayer(points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
            let spotlightFilter = FilterLayer(rects: [CGRect(x: 5, y: 5, width: 30, height: 30)], filterMode: .spotlight)
            let blurFilter = FilterLayer(rects: [CGRect(x: 10, y: 10, width: 30, height: 30)], filterMode: .gaussian)
            let dimLayer = DimensionLayer(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))

            let allLayers: [AnnotationLayer] = [
                rectLayer, ellipseLayer, arrowLayer, counterLayer,
                lineLayer, penLayer, highlighterLayer, spotlightFilter, blurFilter,
                dimLayer
            ]

            // 1. Verify hoverPath generates a valid CGPath for every layer
            for layer in allLayers {
                let path = canvas.hoverPath(for: layer)
                assert(path != nil, "hoverPath must return non-nil CGPath for \(type(of: layer))")
                assert(!path!.isEmpty, "hoverPath must not be empty for \(type(of: layer))")
            }

            // 2. Verify hover state updates for arbitrary layers (rectLayer, counterLayer, etc.)
            doc.addLayer(rectLayer)
            doc.addLayer(counterLayer)

            // Hover over rectLayer
            canvas.updateHoverState(to: rectLayer)
            assert(canvas.hoveredLayer?.id == rectLayer.id, "Setting hover on RectangleLayer must update hoveredLayer")
            assert(canvas.hoverOutlineLayer?.id == rectLayer.id, "Setting hover on RectangleLayer must update hoverOutlineLayer")

            // Hover over counterLayer
            canvas.updateHoverState(to: counterLayer)
            assert(canvas.hoveredLayer?.id == counterLayer.id, "Setting hover on CounterLayer must update hoveredLayer")
            assert(canvas.hoverOutlineLayer?.id == counterLayer.id, "Setting hover on CounterLayer must update hoverOutlineLayer")

            // Clear hover state
            canvas.updateHoverState(to: nil)
            assert(canvas.hoveredLayer == nil, "Hovering away must clear hoveredLayer")
        }

        testRunner("Editor - Top Menubar Glued to Top, Modern Icons, Tooltips with Shortcuts & Hover/Active States") {
            let context = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)

            // 1. Menubar is glued to the top of the container
            let container = panel.contentView!
            assert(panel.toolbarView.superview == container, "toolbarView must be subview of window contentView")
            assert(panel.scrollView?.superview == container, "scrollView must be subview of window contentView")

            // 2. Modern Toolbar Button Hover and Active States
            let btn = ModernToolbarButton(systemName: "arrow.up.right", tooltip: "Arrow [A]")
            assert(btn.tooltipText == "Arrow [A]", "Tooltip must format name and shortcut in square brackets: Arrow [A]")
            assert(btn.layer?.backgroundColor == nil || btn.layer?.backgroundColor == NSColor.clear.cgColor, "Initial state should be clear")

            // Hover state test
            btn.isHovered = true
            assert(btn.layer?.backgroundColor != nil && btn.layer?.backgroundColor != NSColor.clear.cgColor, "Hover state must display hover pill background")

            // Active state test
            btn.isActive = true
            assert(btn.layer?.backgroundColor != nil, "Active state must display active background")

            btn.isActive = false
            btn.isHovered = false

            // 3. Modern Color Button Hover and Active States
            let colBtn = ModernColorButton(hex: "#FF3B30", name: "Red")
            assert(colBtn.tooltipText == "Red", "Color button tooltip must show color name")
            colBtn.isHovered = true
            colBtn.isActive = true
            assert(colBtn.isActive, "Color button must support active selection state")

            // 4. Tooltip Window Scheduling
            let tooltipWin = EditorTooltipWindow.shared
            tooltipWin.schedule(text: "Arrow [A]", for: btn)
            tooltipWin.hide()
        }

        testRunner("Editor - Copy To Clipboard Modern Toast Notification") {
            let context = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)

            // 1. Initial state: no toast
            let container = panel.contentView!
            assert(container.subviews.first(where: { $0.identifier == EditorToastView.sharedIdentifier }) == nil, "No toast initially")

            // 2. Trigger copy notification toast
            panel.showCopiedToClipboardToast()
            let toast = container.subviews.first(where: { $0.identifier == EditorToastView.sharedIdentifier }) as? EditorToastView
            assert(toast != nil, "showCopiedToClipboardToast must present EditorToastView in contentView")
            assert(toast?.material == .hudWindow, "Toast must use .hudWindow material matching cmd+q prompt")
            assert(toast?.layer?.cornerRadius == 16, "Toast corner radius must be 16 matching cmd+q prompt")

            // 3. Repeated copy pulses existing toast without duplicating
            panel.showCopiedToClipboardToast()
            let toasts = container.subviews.filter { $0.identifier == EditorToastView.sharedIdentifier }
            assert(toasts.count == 1, "Repeated copy must not create duplicate toast pills")

            // 4. Trigger image saved toast
            panel.showImageSavedToast()
            let savedToast = container.subviews.first(where: { $0.identifier == EditorToastView.sharedIdentifier }) as? EditorToastView
            assert(savedToast != nil, "showImageSavedToast must present EditorToastView in contentView")
            assert(savedToast?.material == .hudWindow, "Saved toast must use .hudWindow material")
            assert(savedToast?.layer?.cornerRadius == 16, "Saved toast corner radius must be 16")
        }

        testRunner("Editor - UFO X-Com Toolbar Icon & Sleek Resizing Cursors") {
            // 1. UFO X-Com Pointer Icon on Toolbar
            let ufoIcon = ModernToolbarButton.ufoPointerIcon
            assert(ufoIcon.size.width == 18 && ufoIcon.size.height == 18, "UFO pointer toolbar icon must be 18x18")
            assert(ufoIcon.isTemplate, "UFO pointer icon must be marked template for automatic tinting")

            // 2. Toolbar & Canvas integration
            let context = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let canvas = EditorCanvasView(document: doc)
            assert(canvas.document.activeTool == .select, "Default tool is .select")

            let toolbar = EditorToolbarView(canvasView: canvas)
            let selectBtn = toolbar.toolButtons[.select]
            assert(selectBtn != nil, "Toolbar must have a .select tool button")
            assert(toolbar.pinButton?.tooltipText == "Always on Top", "Pin button tooltip must be 'Always on Top'")

            // 4. Sleek Move & Resizing Cursors
            let sleekMove = NSCursor.sleekMove
            assert(sleekMove.image.size.width == 28 && sleekMove.image.size.height == 28, "Sleek move must be 28x28")
            assert(sleekMove.hotSpot == NSPoint(x: 14, y: 14), "Sleek move hot spot must be center (14, 14)")

            let sleekHorizontal = NSCursor.sleekResizeHorizontal
            assert(sleekHorizontal.hotSpot == NSPoint(x: 14, y: 14), "Sleek horizontal resize hot spot must be (14, 14)")

            let sleekVertical = NSCursor.sleekResizeVertical
            assert(sleekVertical.hotSpot == NSPoint(x: 14, y: 14), "Sleek vertical resize hot spot must be (14, 14)")

            let sleekNWSE = NSCursor.sleekResizeDiagonalNWSE
            assert(sleekNWSE.hotSpot == NSPoint(x: 14, y: 14), "Sleek NW-SE diagonal resize hot spot must be (14, 14)")

            let sleekNESW = NSCursor.sleekResizeDiagonalNESW
            assert(sleekNESW.hotSpot == NSPoint(x: 14, y: 14), "Sleek NE-SW diagonal resize hot spot must be (14, 14)")

            // 5. Aliases
            assert(NSCursor.fourDirectionalMove === NSCursor.sleekMove, "fourDirectionalMove must alias sleekMove")
            assert(NSCursor.sleekResizeLeftRight === NSCursor.sleekResizeHorizontal, "sleekResizeLeftRight must alias sleekResizeHorizontal")
            assert(NSCursor.sleekResizeUpDown === NSCursor.sleekResizeVertical, "sleekResizeUpDown must alias sleekResizeVertical")
        }

        testRunner("Editor - Responsive Toolbar 3-Dots Overflow Submenu") {
            let context = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let canvas = EditorCanvasView(document: doc)
            let toolbar = EditorToolbarView(canvasView: canvas)

            // 1. Wide window (900pt): All tools visible, overflow 3-dots hidden
            toolbar.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.select]?.isHidden == false, "Pointer must be visible when wide")
            assert(toolbar.toolButtons[.blur]?.isHidden == false, "Blur must be visible when wide")
            assert(toolbar.overflowButton?.isHidden == true, "3-dots overflow must be hidden when wide")
            assert(toolbar.openButton?.isHidden == false, "Open must be visible")
            assert(toolbar.copyButton?.isHidden == false, "Copy must be visible")
            assert(toolbar.saveButton?.isHidden == false, "Save must be visible")
            assert(toolbar.pinButton?.isHidden == false, "Pin must be visible")

            // 2. Narrow window (450pt): Rightmost tools hide under 3-dots
            toolbar.frame = NSRect(x: 0, y: 0, width: 450, height: 44)
            toolbar.layout()

            // Essential icons strictly preserved
            assert(toolbar.toolButtons[.select]?.isHidden == false, "Pointer must ALWAYS remain visible when narrow")
            assert(toolbar.openButton?.isHidden == false, "Open must ALWAYS remain visible when narrow")
            assert(toolbar.copyButton?.isHidden == false, "Copy must ALWAYS remain visible when narrow")
            assert(toolbar.saveButton?.isHidden == false, "Save must ALWAYS remain visible when narrow")
            assert(toolbar.pinButton?.isHidden == false, "Pin must ALWAYS remain visible when narrow")

            // Rightmost tools collapsed under 3-dots
            assert(toolbar.toolButtons[.blur]?.isHidden == true, "Rightmost tool (Blur) must hide when narrow")
            assert(toolbar.overflowButton?.isHidden == false, "3-dots overflow button must be visible when narrow")

            // 3. Very narrow window (340pt): Still preserves Pointer, Open, Copy, Save, Pin and 3-dots
            toolbar.frame = NSRect(x: 0, y: 0, width: 340, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.select]?.isHidden == false, "Pointer must remain visible even at 340pt")
            assert(toolbar.openButton?.isHidden == false, "Open must remain visible even at 340pt")
            assert(toolbar.copyButton?.isHidden == false, "Copy must remain visible even at 340pt")
            assert(toolbar.saveButton?.isHidden == false, "Save must remain visible even at 340pt")
            assert(toolbar.pinButton?.isHidden == false, "Pin must remain visible even at 340pt")
            assert(toolbar.overflowButton?.isHidden == false, "3-dots overflow button must be visible at 340pt")

            // 4. Overflow menu tool activation & dropdown items matching reference image
            assert(toolbar.dropdownToolDefinitions.count == 10, "Dropdown must contain full suite of remaining tools")
            let titles = toolbar.dropdownToolDefinitions.map { $0.title }
            assert(titles.contains("Arrow"), "Dropdown must contain Arrow")
            assert(!titles.contains("Speech Bubble"), "Dropdown must NOT contain removed Speech Bubble")
            assert(titles.contains("Ruler (1 or 2)"), "Dropdown must contain Ruler (1 or 2)")
            assert(titles.contains("Rectangle"), "Dropdown must contain Rectangle")
            assert(!titles.contains("Backdrop"), "Dropdown must NOT contain removed Backdrop")
            assert(titles.contains("Freehand Drawing"), "Dropdown must contain Freehand Drawing")
            assert(!titles.contains("Magnifier"), "Dropdown must NOT contain removed Magnifier")
            assert(!titles.contains("Add Capture"), "Dropdown must NOT contain removed Add Capture")
            assert(!titles.contains("Text"), "Dropdown must NOT contain removed Text")
            assert(titles.contains("Blur"), "Dropdown must contain renamed Blur")
            assert(!titles.contains("Blur/Erase"), "Dropdown must NOT contain Blur/Erase")
            assert(titles.contains("Highlighter"), "Dropdown must contain Highlighter")
            assert(titles.contains("Spotlight"), "Dropdown must contain Spotlight")
            assert(titles.contains("Counter"), "Dropdown must contain Counter")
            assert(titles.contains("Oval"), "Dropdown must contain Oval")
            assert(titles.contains("Line"), "Dropdown must contain Line")

            canvas.document.activeTool = .blur
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.overflowButton?.isActive == true, "3-dots overflow button must show active state when an overflowed tool is active")

            canvas.document.activeTool = .counter
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.overflowButton?.isActive == true, "3-dots overflow button must show active state for dropdown tool (Counter)")
        }

        testRunner("Editor - Cmd + Mousewheel Zooms In and Out") {
            let context = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)
            guard let sv = panel.scrollView else {
                fatalError("scrollView must exist in EditorPanel")
            }
            sv.magnification = 1.0
            panel.canvasView.zoomScale = 1.0

            // 1. Scroll Up with Cmd (+deltaY) -> Zooms In
            let cgScrollUp = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
            cgScrollUp.flags = .maskCommand
            let eventUp = NSEvent(cgEvent: cgScrollUp)!
            panel.canvasView.scrollWheel(with: eventUp)

            assert(sv.magnification > 1.0, "Cmd + mousewheel up must increase magnification (zoomed in)")
            assert(panel.canvasView.zoomScale == sv.magnification, "canvasView.zoomScale must track sv.magnification")
            let magAfterZoomIn = sv.magnification

            // 2. Scroll Down with Cmd (-deltaY) -> Zooms Out
            let cgScrollDown = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)!
            cgScrollDown.flags = .maskCommand
            let eventDown = NSEvent(cgEvent: cgScrollDown)!
            panel.canvasView.scrollWheel(with: eventDown)

            assert(sv.magnification < magAfterZoomIn, "Cmd + mousewheel down must decrease magnification (zoomed out)")
            assert(panel.canvasView.zoomScale == sv.magnification, "canvasView.zoomScale must track sv.magnification")

            // 3. Scroll without Cmd -> Does not change magnification
            let currentMag = sv.magnification
            let cgScrollNoCmd = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
            cgScrollNoCmd.flags = []
            let eventNoCmd = NSEvent(cgEvent: cgScrollNoCmd)!
            panel.canvasView.scrollWheel(with: eventNoCmd)
            assert(sv.magnification == currentMag, "Mousewheel without Cmd must NOT alter magnification")

            // 4. Precise scrolling deltas (trackpad / smooth wheel with Cmd)
            let cgPreciseUp = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 15, wheel2: 0, wheel3: 0)!
            cgPreciseUp.flags = .maskCommand
            let eventPreciseUp = NSEvent(cgEvent: cgPreciseUp)!
            let magBeforePrecise = sv.magnification
            panel.handleZoomWheel(with: eventPreciseUp)
            assert(sv.magnification > magBeforePrecise, "Precise Cmd + scrolling must zoom in smoothly")

            // 5. Clamping enforcement: cannot exceed maxMagnification or minMagnification
            sv.magnification = 9.9
            panel.handleZoomWheel(with: eventUp)
            assert(sv.magnification <= sv.maxMagnification, "Zoom must not exceed maxMagnification (10.0)")

            sv.magnification = 0.06
            panel.handleZoomWheel(with: eventDown)
            assert(sv.magnification >= sv.minMagnification, "Zoom must not fall below minMagnification (0.05)")

            // 6. Reset to 100% zoom button
            assert(panel.toolbarView.zoomResetButton != nil, "Toolbar must have zoomResetButton")
            sv.magnification = 3.25
            panel.canvasView.zoomScale = 3.25
            panel.toolbarView.zoomResetButton?.onAction?()
            assert(sv.magnification == 1.0, "Clicking zoomResetButton must reset magnification to 1.0 (100%)")
            assert(panel.canvasView.zoomScale == 1.0, "canvasView.zoomScale must be 1.0 after reset")
            assert(panel.toolbarView.metaLabel.stringValue.contains("(100%)"), "metaLabel must display (100%) after zoom reset")

            panel.close()
        }

        testRunner("Editor - Right Mouse Button Canvas Panning Direction") {
            let context = CGContext(
                data: nil,
                width: 1000,
                height: 1000,
                bitsPerComponent: 8,
                bytesPerRow: 4000,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)
            panel.setFrame(NSRect(x: 100, y: 100, width: 600, height: 500), display: true)
            guard let sv = panel.scrollView, let clipView = sv.contentView as? CenteringClipView else {
                fatalError("scrollView and CenteringClipView must exist")
            }
            sv.magnification = 1.0
            panel.canvasView.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
            clipView.scroll(to: NSPoint(x: 200, y: 200))

            let startOrigin = clipView.bounds.origin

            // 1. Right Mouse Down at (100, 100)
            let downEvent = NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 100, y: 100),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1.0
            )!
            panel.canvasView.rightMouseDown(with: downEvent)

            // 2. Drag UP in window coordinates (+Y in macOS window space, e.g. from y=100 to y=150)
            // Moving mouse UP on screen should drag canvas content UP, increasing clipView scroll origin Y
            let dragUpEvent = NSEvent.mouseEvent(
                with: .rightMouseDragged,
                location: NSPoint(x: 100, y: 150),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1.0
            )!
            panel.canvasView.rightMouseDragged(with: dragUpEvent)

            assert(clipView.bounds.origin.y > startOrigin.y, "Dragging mouse UP (+Y) must move clip origin up (> startOrigin.y), not flipped")
            let originAfterDragUp = clipView.bounds.origin

            // 3. Drag DOWN in window coordinates (-Y in macOS window space, e.g. from y=150 to y=80)
            // Moving mouse DOWN on screen should drag canvas content DOWN, decreasing clipView scroll origin Y
            let dragDownEvent = NSEvent.mouseEvent(
                with: .rightMouseDragged,
                location: NSPoint(x: 100, y: 80),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 3,
                clickCount: 1,
                pressure: 1.0
            )!
            panel.canvasView.rightMouseDragged(with: dragDownEvent)

            assert(clipView.bounds.origin.y < originAfterDragUp.y, "Dragging mouse DOWN (-Y) must move clip origin down (< originAfterDragUp.y)")

            let upEvent = NSEvent.mouseEvent(
                with: .rightMouseUp,
                location: NSPoint(x: 100, y: 80),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 4,
                clickCount: 1,
                pressure: 0.0
            )!
            panel.canvasView.rightMouseUp(with: upEvent)

            // 4. Zoomed-In Dragging: Moves in physical screen pixels (1:1 pinned under cursor), not multiplied by zoom
            sv.magnification = 5.0
            panel.canvasView.zoomScale = 5.0
            clipView.scroll(to: NSPoint(x: 500, y: 500))

            let ptBeforeZoomDrag = clipView.convert(NSPoint(x: 200, y: 200), from: nil)
            let downZoom = NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 200, y: 200),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 5,
                clickCount: 1,
                pressure: 1.0
            )!
            panel.canvasView.rightMouseDown(with: downZoom)

            let dragZoom = NSEvent.mouseEvent(
                with: .rightMouseDragged,
                location: NSPoint(x: 210, y: 190), // 10px right, 10px down in screen pixels
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 6,
                clickCount: 1,
                pressure: 1.0
            )!
            panel.canvasView.rightMouseDragged(with: dragZoom)

            let ptAfterZoomDrag = clipView.convert(NSPoint(x: 210, y: 190), from: nil)
            assert(abs(ptBeforeZoomDrag.x - ptAfterZoomDrag.x) < 0.001, "Canvas point must remain pinned under cursor when zoomed in (X)")
            assert(abs(ptBeforeZoomDrag.y - ptAfterZoomDrag.y) < 0.001, "Canvas point must remain pinned under cursor when zoomed in (Y)")

            panel.close()
        }

        testRunner("Editor - Window Width Drives Responsive Toolbar Collapsing Without Width Constraint") {
            let context = CGContext(
                data: nil,
                width: 400,
                height: 400,
                bitsPerComponent: 8,
                bytesPerRow: 1600,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)

            // 1. Initial wide window: Toolbar fitting size must not force large minimum width
            assert(panel.contentView?.fittingSize.width ?? 0 <= 320.0, "Content view fitting size must not force wide window")

            // 2. Window resizing to 900pt (Wide): Window decides width; all tools visible, 3-dots hidden
            panel.setFrame(NSRect(x: 100, y: 100, width: 900, height: 500), display: true)
            assert(panel.frame.width == 900.0)
            assert(panel.toolbarView.toolButtons[.select]?.isHidden == false, "Pointer visible at 900pt")
            assert(panel.toolbarView.toolButtons[.blur]?.isHidden == false, "Blur visible at 900pt")
            assert(panel.toolbarView.overflowButton?.isHidden == true, "3-dots overflow button hidden when all tools fit at 900pt")

            // 3. Window resizing to 600pt (Medium): Window decides width; Blur hides under 3-dots
            panel.setFrame(NSRect(x: 100, y: 100, width: 600, height: 500), display: true)
            assert(panel.frame.width == 600.0)
            assert(panel.toolbarView.toolButtons[.select]?.isHidden == false, "Pointer visible at 600pt")
            assert(panel.toolbarView.toolButtons[.blur]?.isHidden == true, "Blur hidden at 600pt")
            assert(panel.toolbarView.overflowButton?.isHidden == false, "3-dots overflow visible at 600pt")

            // 4. Window resizing to 280pt (Narrow): Menu must NOT force window to stay wider than 280pt
            panel.setFrame(NSRect(x: 100, y: 100, width: 280, height: 500), display: true)
            assert(panel.frame.width == 280.0, "Window must successfully shrink to 280pt without toolbar blocking it")
            assert(panel.toolbarView.bounds.width == 280.0, "Toolbar bounds must match window width")

            // Essential buttons strictly preserved at 280pt
            assert(panel.toolbarView.toolButtons[.select]?.isHidden == false, "Pointer strictly visible at 280pt")
            assert(panel.toolbarView.overflowButton?.isHidden == false, "3-dots overflow strictly visible at 280pt")
            assert(panel.toolbarView.openButton?.isHidden == false, "Open strictly visible at 280pt")
            assert(panel.toolbarView.copyButton?.isHidden == false, "Copy strictly visible at 280pt")
            assert(panel.toolbarView.saveButton?.isHidden == false, "Save strictly visible at 280pt")
            assert(panel.toolbarView.pinButton?.isHidden == false, "Pin strictly visible at 280pt")

            // Non-essential tools cleanly collapsed into 3-dots
            assert(panel.toolbarView.toolButtons[.arrow]?.isHidden == true, "Arrow collapsed at 280pt")
            assert(panel.toolbarView.toolButtons[.blur]?.isHidden == true, "Blur collapsed at 280pt")

            panel.close()
        }

        testRunner("Editor - Oval Dragging Edge Margin and 4-Point Axis Resizing") {
            let oval = EllipseLayer(
                rect: CGRect(x: 100, y: 100, width: 200, height: 100),
                fillStyle: .outline
            )

            // 1. No dragging from middle
            let center = CGPoint(x: 200, y: 150)
            assert(!oval.contains(point: center), "Outline oval must NOT contain center point (no dragging from middle)")

            let innerPoint = CGPoint(x: 200, y: 130)
            assert(!oval.contains(point: innerPoint), "Outline oval must NOT contain interior point away from edge")

            // 2. Dragging allowed only from edge plus margin
            let topEdge = CGPoint(x: 200, y: 100)
            assert(oval.contains(point: topEdge), "Outline oval must contain top edge point")

            let topNearEdge = CGPoint(x: 200, y: 96)
            assert(oval.contains(point: topNearEdge), "Outline oval must contain point within edge margin")

            let farOutside = CGPoint(x: 200, y: 60)
            assert(!oval.contains(point: farOutside), "Outline oval must not contain point outside margin")

            // Solid oval contains center
            let solidOval = EllipseLayer(
                rect: CGRect(x: 100, y: 100, width: 200, height: 100),
                fillStyle: .solid
            )
            assert(solidOval.contains(point: center), "Solid oval must contain center point")

            // 3. Exactly 4 handles: Corner dots removed, only vertical and horizontal handles
            let handles = oval.getHandlePoints()
            assert(handles.count == 4, "Oval must have exactly 4 handles (corner dots removed)")
            assert(handles[0] == CGPoint(x: 200, y: 100), "Handle 0 must be Top-Center")
            assert(handles[1] == CGPoint(x: 300, y: 150), "Handle 1 must be Right-Center")
            assert(handles[2] == CGPoint(x: 200, y: 200), "Handle 2 must be Bottom-Center")
            assert(handles[3] == CGPoint(x: 100, y: 150), "Handle 3 must be Left-Center")

            // 4. Hit testing handles
            assert(oval.hitTestHandle(point: CGPoint(x: 200, y: 100)) == 0, "Top handle hit tested")
            assert(oval.hitTestHandle(point: CGPoint(x: 300, y: 150)) == 1, "Right handle hit tested")
            assert(oval.hitTestHandle(point: CGPoint(x: 200, y: 200)) == 2, "Bottom handle hit tested")
            assert(oval.hitTestHandle(point: CGPoint(x: 100, y: 150)) == 3, "Left handle hit tested")
            assert(oval.hitTestHandle(point: CGPoint(x: 100, y: 100)) == nil, "Corner dot hit test must be nil (no corner handle)")

            // 5. Vertical Resizing: Top handle changes height only
            oval.updateHandle(index: 0, to: CGPoint(x: 180, y: 80))
            assert(oval.rect.minX == 100 && oval.rect.maxX == 300, "Vertical resize must not alter width or X coordinates")
            assert(oval.rect.minY == 80 && oval.rect.height == 120, "Vertical resize must update top and height")

            // 6. Horizontal Resizing: Right handle changes width only
            oval.updateHandle(index: 1, to: CGPoint(x: 350, y: 120))
            assert(oval.rect.minY == 80 && oval.rect.maxY == 200, "Horizontal resize must not alter height or Y coordinates")
            assert(oval.rect.maxX == 350 && oval.rect.width == 250, "Horizontal resize must update right and width")
        }

        testRunner("Editor - Welcome CTA Panel & Drag-and-Drop Image Acceptance") {
            let welcome = WelcomePanel()
            assert(welcome.frame.width == 520, "WelcomePanel width must be 520pt")
            assert(welcome.frame.height == 360, "WelcomePanel height must be 360pt")
            assert(welcome.dropView.openButton.isHidden == false, "Open button in welcome drop view must be visible")

            // Verify supported file extension filtering
            let supported = ["photo.png", "image.jpg", "scan.jpeg", "layer.tiff", "shot.heic", "icon.webp", "anim.gif", "drawing.bmp"]
            for name in supported {
                let url = URL(fileURLWithPath: "/tmp/\(name)")
                let ext = url.pathExtension.lowercased()
                assert(WelcomeDropView.supportedExtensions.contains(ext), "Extension \(ext) must be supported")
            }

            let unsupported = ["document.pdf", "readme.txt", "archive.zip", "script.sh"]
            for name in unsupported {
                let url = URL(fileURLWithPath: "/tmp/\(name)")
                let ext = url.pathExtension.lowercased()
                assert(!WelcomeDropView.supportedExtensions.contains(ext), "Extension \(ext) must be rejected")
            }

            welcome.close()
        }

        testRunner("Editor - Open Button Action & Drag-and-Drop on EditorPanel") {
            let context = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let doc = EditorDocument(image: context.makeImage()!)
            let panel = EditorPanel(document: doc)

            var openRequested = false
            panel.toolbarView.onOpenRequested = {
                openRequested = true
            }
            panel.toolbarView.openButton?.onAction?()
            assert(openRequested == true, "Triggering openButton action must fire onOpenRequested")

            // Verify drag target overlay toggle
            panel.showDropTargetOverlay(true)
            panel.showDropTargetOverlay(false)

            panel.close()
        }
    }
}



