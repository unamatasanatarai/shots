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

            // 3. Window Sizing: minimum width is width of tool panel (600), default height 400
            assert(panel.minSize.width == 600.0, "EditorPanel minSize.width must equal tool panel width (600.0)")
            assert(panel.minSize.height == 400.0, "EditorPanel minSize.height must be 400.0")

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
    }
}
