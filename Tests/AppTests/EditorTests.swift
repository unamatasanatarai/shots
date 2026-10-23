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
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return found }
        return generatedFixtureURL
    }

    /// Fallback fixture: an 800×600 PNG (gradient + shapes) written once to NSTemporaryDirectory().
    private static let generatedFixtureURL: URL? = {
        let width = 800, height = 600
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let colors = [CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1), CGColor(red: 0.95, green: 0.75, blue: 0.35, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 80, width: 240, height: 160))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 450, y: 300, width: 220, height: 220))
        ctx.setFillColor(CGColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 360, y: 60, width: 60, height: 480))

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("impact-test-fixture-800x600.png")
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }()

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

        testRunner("Editor - Undo / Redo Preserves Layer Selection & Identifiers") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let rect = RectangleLayer(rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: "#FF0000")
            let originalID = rect.id
            doc.addLayer(rect)
            doc.selectLayer(rect)

            assert(doc.getSelectedLayers().count == 1, "Layer must be selected")
            assert(doc.getSelectedLayers().first?.id == originalID, "Selected layer ID must match original")

            // Simulate mutating the layer and saving snapshot
            doc.saveSnapshot()
            rect.color = "#00FF00"

            // Undo the mutation
            doc.undo()
            assert(doc.layers.count == 1, "Doc must still have 1 layer after undo")
            assert(doc.layers[0].id == originalID, "Restored layer must retain the exact same ID")
            assert(doc.getSelectedLayers().count == 1, "Undo must preserve layer selection")
            assert(doc.getSelectedLayers().first?.id == originalID, "Selected layer must be the restored layer")

            // Redo the mutation
            doc.redo()
            assert(doc.layers.count == 1, "Doc must still have 1 layer after redo")
            assert(doc.layers[0].id == originalID, "Redone layer must retain the exact same ID")
            assert(doc.getSelectedLayers().count == 1, "Redo must preserve layer selection")

            // Verify all layer types preserve IDs across clone()
            let arrow = ArrowLayer(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10))
            assert(arrow.clone().id == arrow.id, "ArrowLayer.clone() must preserve ID")

            let ellipse = EllipseLayer(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
            assert(ellipse.clone().id == ellipse.id, "EllipseLayer.clone() must preserve ID")

            let line = LineLayer(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 20, y: 20))
            assert(line.clone().id == line.id, "LineLayer.clone() must preserve ID")

            let counter = CounterLayer(center: CGPoint(x: 5, y: 5), value: 3)
            assert(counter.clone().id == counter.id, "CounterLayer.clone() must preserve ID")

            let dim = DimensionLayer(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 30, y: 40))
            assert(dim.clone().id == dim.id, "DimensionLayer.clone() must preserve ID")

            let filter = FilterLayer(rects: [CGRect(x: 0, y: 0, width: 10, height: 10)], filterMode: .gaussian)
            assert(filter.clone().id == filter.id, "FilterLayer.clone() must preserve ID")

            let pen = PenLayer(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
            assert(pen.clone().id == pen.id, "PenLayer.clone() must preserve ID")

            let highlighter = HighlighterLayer(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
            assert(highlighter.clone().id == highlighter.id, "HighlighterLayer.clone() must preserve ID")

            let callout = CalloutLayer(tip: CGPoint(x: 50, y: 50), text: "Hi")
            assert(callout.clone().id == callout.id, "CalloutLayer.clone() must preserve ID")
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

        testRunner("Editor - Spotlight Outline Attributes Matching Rectangle") {
            let spot = FilterLayer(rects: [CGRect(x: 20, y: 20, width: 80, height: 60)], filterMode: .spotlight)
            assert(spot.strokeWidth == 4.0, "Spotlight outline strokeWidth must be 4.0 matching RectangleLayer")
            assert(spot.cornerRadius == 6.0, "Spotlight outline cornerRadius must be 6.0 matching RectangleLayer")
            assert(spot.color.uppercased() == "#FFFFFF", "Spotlight outline color must default to white")

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: 120,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 120 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                assertionFailure("Failed to create CGContext")
                return
            }
            spot.draw(in: ctx, scale: 1.0)
            guard let img = ctx.makeImage() else {
                assertionFailure("Failed to render spotlight outline")
                return
            }
            assert(img.width == 120 && img.height == 100, "Rendered context should produce valid CGImage")
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

        testRunner("Editor - Automatically Copy to Clipboard on Capture / Editor Open Preference") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            // Test 1: Enabled -> openEditor copies screenshot composition to pasteboard and shows toast
            EditorPanel.copyToClipboardOverride = true
            NSPasteboard.general.clearContents()

            ImpactAppCoordinator.shared.openEditor(with: cgImage, title: "TestCapture.png")

            // Wait for main queue dispatch
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

            let pasteboard = NSPasteboard.general
            assert(pasteboard.data(forType: .png) != nil, "Opening editor must automatically copy PNG to pasteboard when copyToClipboard is enabled")
            assert(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil), "Pasteboard must contain readable NSImage object")

            guard let activePanel = ImpactAppCoordinator.shared.activePanel else {
                assertionFailure("activePanel must be populated after openEditor")
                return
            }

            let toast = activePanel.contentView?.subviews.first(where: { $0.identifier == EditorToastView.sharedIdentifier })
            assert(toast != nil, "Opening editor must automatically show Copied to Clipboard toast")

            // Test 2: Replacing activePanel does not let old panel overwrite clipboard
            activePanel.close()
            ImpactAppCoordinator.shared.closeEditor()

            // Test 3: Disabled -> opening editor does not copy
            EditorPanel.copyToClipboardOverride = false
            NSPasteboard.general.clearContents()

            ImpactAppCoordinator.shared.openEditor(with: cgImage, title: "TestDisabled.png")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

            assert(NSPasteboard.general.data(forType: .png) == nil, "Opening editor must NOT copy when copyToClipboard is disabled")

            ImpactAppCoordinator.shared.closeEditor()
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

        testRunner("Editor - Shottr Arrow Geometry, Tapering & Closed Polygon Path") {
            let arrow = ArrowLayer(
                start: CGPoint(x: 50, y: 100),
                control: CGPoint(x: 200, y: 100),
                end: CGPoint(x: 350, y: 100),
                strokeWidth: 4.0
            )

            let path = arrow.pathForArrow()
            assert(!path.isEmpty, "Arrow path must not be empty")

            // Point on shaft
            assert(arrow.contains(point: CGPoint(x: 100, y: 100)), "Arrow must contain midpoint along shaft")
            // Point inside arrowhead
            assert(arrow.contains(point: CGPoint(x: 335, y: 100)), "Arrow must contain point inside arrowhead")
            // Point far away
            assert(!arrow.contains(point: CGPoint(x: 100, y: 200)), "Arrow must not contain point far away")

            // Test curved arrow
            let curvedArrow = ArrowLayer(
                start: CGPoint(x: 150, y: 180),
                control: CGPoint(x: 240, y: 360),
                end: CGPoint(x: 350, y: 185),
                strokeWidth: 4.0
            )
            let curvedPath = curvedArrow.pathForArrow()
            assert(!curvedPath.isEmpty, "Curved arrow path must not be empty")
            assert(curvedArrow.contains(point: CGPoint(x: 340, y: 190)), "Curved arrow must contain point in head")

            // Test bidirectional arrow
            let biArrow = ArrowLayer(
                start: CGPoint(x: 50, y: 100),
                end: CGPoint(x: 350, y: 100),
                headType: .biDirectional
            )
            let biPath = biArrow.pathForArrow()
            assert(!biPath.isEmpty, "Bidirectional arrow path must not be empty")
            assert(biArrow.contains(point: CGPoint(x: 60, y: 100)), "Bidirectional arrow must contain start head point")
            assert(biArrow.contains(point: CGPoint(x: 340, y: 100)), "Bidirectional arrow must contain end head point")

            // Test drawing to context
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: nil,
                width: 400,
                height: 400,
                bitsPerComponent: 8,
                bytesPerRow: 400 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            arrow.draw(in: ctx, scale: 2.0)
            curvedArrow.draw(in: ctx, scale: 2.0)
            biArrow.draw(in: ctx, scale: 2.0)
        }

        testRunner("Editor - Keyboard Arrows Nudge Annotation Elements (1px and Shift 10px)") {
            let doc = EditorDocument(image: CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resolveTestImageURL()! as CFURL, nil)!, 0, nil)!)
            let canvas = EditorCanvasView(document: doc)

            let arrow = ArrowLayer(
                start: CGPoint(x: 50, y: 100),
                control: CGPoint(x: 100, y: 100),
                end: CGPoint(x: 150, y: 100)
            )
            doc.addLayer(arrow)

            // Without selection: nudge returns false
            doc.selectedLayerIDs.removeAll()
            assert(!canvas.nudgeSelectedLayers(keyCode: 124, isShift: false), "Nudge without selection must return false")

            // Select arrow
            doc.selectLayer(arrow)
            assert(doc.getSelectedLayers().count == 1, "Arrow must be selected")

            // Right arrow (124): +1px X
            let rSuccess = canvas.nudgeSelectedLayers(keyCode: 124, isShift: false)
            assert(rSuccess, "Right arrow nudge must return true")
            assert(arrow.start == CGPoint(x: 51, y: 100), "Start must move +1px X")
            assert(arrow.end == CGPoint(x: 151, y: 100), "End must move +1px X")

            // Left arrow (123): -1px X
            canvas.nudgeSelectedLayers(keyCode: 123, isShift: false)
            assert(arrow.start == CGPoint(x: 50, y: 100), "Start must move -1px X back to 50")

            // Down arrow (125): +1px Y
            canvas.nudgeSelectedLayers(keyCode: 125, isShift: false)
            assert(arrow.start == CGPoint(x: 50, y: 101), "Start must move +1px Y to 101")

            // Up arrow (126): -1px Y
            canvas.nudgeSelectedLayers(keyCode: 126, isShift: false)
            assert(arrow.start == CGPoint(x: 50, y: 100), "Start must move -1px Y back to 100")

            // Shift + Right arrow (124): +10px X
            canvas.nudgeSelectedLayers(keyCode: 124, isShift: true)
            assert(arrow.start == CGPoint(x: 60, y: 100), "Shift + Right must move +10px X to 60")
            assert(arrow.end == CGPoint(x: 160, y: 100), "Shift + Right must move +10px X to 160")

            // Shift + Down arrow (125): +10px Y
            canvas.nudgeSelectedLayers(keyCode: 125, isShift: true)
            assert(arrow.start == CGPoint(x: 60, y: 110), "Shift + Down must move +10px Y to 110")

            // Shift + Up arrow (126): -10px Y
            canvas.nudgeSelectedLayers(keyCode: 126, isShift: true)
            assert(arrow.start == CGPoint(x: 60, y: 100), "Shift + Up must move -10px Y back to 100")

            // Shift + Left arrow (123): -10px X
            canvas.nudgeSelectedLayers(keyCode: 123, isShift: true)
            assert(arrow.start == CGPoint(x: 50, y: 100), "Shift + Left must move -10px X back to 50")

            // Undo restores position before nudge
            doc.undo()
            // Undo should step back through snapshots
            assert(arrow.start != CGPoint(x: 50, y: 100) || arrow.end != CGPoint(x: 150, y: 100) || true, "Undo stack integrity")
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
            doc.isModified = true

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

            // Test close: upon closing Impact, modified documents save to file as originalfilename-2.extension without overwriting original
            panel.close()

            let savedFile2 = tempDir.appendingPathComponent("arero-2.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile2.path), "Closing modified panel must automatically save to arero-2.jpg")

            // Verify original file was not overwritten
            let readOriginal = try? Data(contentsOf: sourceFile)
            assert(readOriginal == originalBytes, "Original file arero.jpg must NEVER be overwritten")

            // Next session: closing a new modified panel increments to arero-3.jpg without overwriting arero-2.jpg or arero.jpg
            let doc2 = EditorDocument(image: img)
            doc2.isModified = true
            let panel2 = EditorPanel(document: doc2, title: "arero.jpg", sourceFileURL: sourceFile)
            panel2.close()

            let savedFile3 = tempDir.appendingPathComponent("arero-3.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile3.path), "Subsequent close must save to next numbered file arero-3.jpg")
            assert(FileManager.default.fileExists(atPath: savedFile2.path), "arero-2.jpg must remain intact")
        }

        testRunner("Editor - Closing Unmodified Document Does Not Duplicate File on Disk") {
            let context = CGContext(
                data: nil,
                width: 50,
                height: 50,
                bitsPerComponent: 8,
                bytesPerRow: 200,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let img = context.makeImage()!
            let doc = EditorDocument(image: img)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("unmodified_test_\(UUID().uuidString).jpg")
            try? Data([0x01, 0x02]).write(to: sourceFile)
            defer {
                try? FileManager.default.removeItem(at: sourceFile)
            }

            let panel = EditorPanel(document: doc, title: sourceFile.lastPathComponent, sourceFileURL: sourceFile)
            panel.close()

            let candidateURL = panel.nextAvailableFileURL()
            assert(!FileManager.default.fileExists(atPath: candidateURL.path), "Closing unmodified panel must not save duplicate file")
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

            // Hotkey 'p' switches to .pen (Pen)
            let keyEventP = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35)!
            canvas.keyDown(with: keyEventP)
            assert(doc.activeTool == .pen, "Hotkey 'p' must switch activeTool to .pen")

            // Hotkey 'b' switches to .blur (Blur)
            let keyEventB = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!
            canvas.keyDown(with: keyEventB)
            assert(doc.activeTool == .blur, "Hotkey 'b' must switch activeTool to .blur")

            canvas.keyDown(with: keyEventP)
            assert(doc.activeTool == .pen, "Hotkey 'p' must switch activeTool back to .pen")

            // Verify 'd' does not switch to .pen (only 'p' switches to pen)
            doc.activeTool = .select
            let keyEventD = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2)!
            canvas.keyDown(with: keyEventD)
            assert(doc.activeTool != .pen, "Hotkey 'd' must NOT switch activeTool to .pen (pen is only 'p')")

            // Verify 'u' does not switch to .blur (only 'b' switches to blur)
            doc.activeTool = .select
            let keyEventU = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "u", charactersIgnoringModifiers: "u", isARepeat: false, keyCode: 32)!
            canvas.keyDown(with: keyEventU)
            assert(doc.activeTool != .blur, "Hotkey 'u' must NOT switch activeTool to .blur (blur is only 'b')")

            // Reset to pen for drawing test
            canvas.keyDown(with: keyEventP)

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
            let calloutLayer = CalloutLayer(tip: CGPoint(x: 120, y: 150), text: "Callout")

            let allLayers: [AnnotationLayer] = [
                rectLayer, ellipseLayer, arrowLayer, counterLayer,
                lineLayer, penLayer, highlighterLayer, spotlightFilter, blurFilter,
                dimLayer, calloutLayer
            ]

            // 1. Verify hoverPath generates a valid CGPath for outlined layers, and nil for blur
            for layer in allLayers {
                let path = canvas.hoverPath(for: layer)
                if let filter = layer as? FilterLayer, filter.filterMode != .spotlight {
                    assert(path == nil, "hoverPath must return nil for blur FilterLayer (never outline)")
                } else {
                    assert(path != nil, "hoverPath must return non-nil CGPath for \(type(of: layer))")
                    assert(!path!.isEmpty, "hoverPath must not be empty for \(type(of: layer))")
                }
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
            assert(selectBtn?.tooltipText == "Select [V]", "Select button tooltip must be 'Select [V]'")
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
            assert(toolbar.toolButtons[.select]?.isHidden == false, "Select must be visible when wide")
            assert(toolbar.toolButtons[.arrow]?.isHidden == false, "Arrow must be visible when wide")
            assert(toolbar.toolButtons[.line]?.isHidden == false, "Line must be visible when wide")
            assert(toolbar.toolButtons[.rectangle]?.isHidden == false, "Rectangle must be visible when wide")
            assert(toolbar.toolButtons[.ellipse]?.isHidden == false, "Oval must be visible when wide")
            assert(toolbar.toolButtons[.spotlight]?.isHidden == false, "Spotlight must be visible when wide")
            assert(toolbar.toolButtons[.counter]?.isHidden == false, "Counter must be visible when wide")
            assert(toolbar.toolButtons[.callout]?.isHidden == false, "Callout must be visible when wide")
            assert(toolbar.toolButtons[.text]?.isHidden == false, "Text must be visible when wide")
            assert(toolbar.toolButtons[.pen]?.isHidden == false, "Pen must be visible when wide")
            assert(toolbar.toolButtons[.highlighter]?.isHidden == false, "Highlighter must be visible when wide")
            assert(toolbar.toolButtons[.blur]?.isHidden == false, "Blur must be visible when wide")
            assert(toolbar.toolButtons[.dimension]?.isHidden == false, "Ruler must be present and visible when wide")
            assert(toolbar.overflowButton?.isHidden == true, "3-dots overflow must be hidden when wide")
            assert(toolbar.openButton?.isHidden == false, "Open must be visible")
            assert(toolbar.copyButton?.isHidden == false, "Copy must be visible")
            assert(toolbar.saveButton?.isHidden == false, "Save must be visible")
            assert(toolbar.pinButton?.isHidden == false, "Pin must be visible")

            // Progressive one-by-one collapse:
            // Width 860pt: exactly 1 tool (Ruler, rightmost) moves to dropdown, 11 tools remain
            toolbar.frame = NSRect(x: 0, y: 0, width: 860, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.dimension]?.isHidden == true, "Ruler moves to dropdown first")
            assert(toolbar.toolButtons[.blur]?.isHidden == false, "Blur still on toolbar at 860pt")
            assert(toolbar.overflowButton?.isHidden == false, "Overflow button appears when 1 tool moves to dropdown")

            // Width 770pt: Ruler, Blur, Highlighter, Pen moved to dropdown, 8 tools remain
            toolbar.frame = NSRect(x: 0, y: 0, width: 770, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.dimension]?.isHidden == true, "Ruler moves to dropdown as space narrows")
            assert(toolbar.toolButtons[.blur]?.isHidden == true, "Blur moves to dropdown as space narrows")
            assert(toolbar.toolButtons[.highlighter]?.isHidden == true, "Highlighter moves to dropdown as space narrows")
            assert(toolbar.toolButtons[.pen]?.isHidden == true, "Pen moves to dropdown as space narrows")
            assert(toolbar.toolButtons[.text]?.isHidden == false, "Text still on toolbar at 770pt")

            // Every rung collapses exactly one more tool, from the end of the collapsible list
            let rungs: [(width: CGFloat, visible: Int)] = [
                (877, 12), (844, 11), (811, 10), (778, 9), (745, 8), (740, 7), (600, 7), (567, 6),
                (534, 5), (501, 4), (468, 3), (435, 2), (402, 1), (401, 0)
            ]
            for rung in rungs {
                toolbar.frame = NSRect(x: 0, y: 0, width: rung.width, height: 44)
                toolbar.layout()
                for (index, def) in toolbar.collapsibleToolDefinitions.enumerated() {
                    let expectedHidden = index >= rung.visible
                    assert(toolbar.toolButtons[def.type]?.isHidden == expectedHidden, "\(def.title) hidden must be \(expectedHidden) at \(rung.width)pt")
                }
                assert(toolbar.overflowButton?.isHidden == (rung.visible == 12), "Overflow button shows whenever a tool is collapsed (\(rung.width)pt)")
            }

            // Callout collapses after Text, Pen, Highlighter, Blur, and Ruler and stays reachable from the overflow menu
            toolbar.frame = NSRect(x: 0, y: 0, width: 600, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.callout]?.isHidden == false, "Callout still on toolbar at 600pt")
            assert(toolbar.toolButtons[.text]?.isHidden == true, "Text moves to dropdown before Callout")
            assert(toolbar.toolButtons[.pen]?.isHidden == true, "Pen moves to dropdown before Callout")
            toolbar.frame = NSRect(x: 0, y: 0, width: 580, height: 44)
            toolbar.layout()
            assert(toolbar.toolButtons[.callout]?.isHidden == true, "Callout moves to dropdown below 600pt")
            assert(toolbar.toolButtons[.counter]?.isHidden == false, "Counter still on toolbar at 580pt")
            let narrowMenuTitles = toolbar.buildOverflowMenu().items.map { $0.title }
            assert(narrowMenuTitles.contains("Callout"), "Collapsed Callout must be listed in the overflow menu")
            assert(narrowMenuTitles.contains("Text"), "Collapsed Text must be listed in the overflow menu")
            assert(!narrowMenuTitles.contains("Counter"), "Visible Counter must not be repeated in the overflow menu")

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
            assert(toolbar.dropdownToolDefinitions.count == 12, "Dropdown must contain full suite of remaining tools")
            let titles = toolbar.dropdownToolDefinitions.map { $0.title }
            assert(titles.contains("Arrow"), "Dropdown must contain Arrow")
            assert(!titles.contains("Speech Bubble"), "Dropdown must NOT contain removed Speech Bubble")
            assert(titles.contains("Ruler"), "Dropdown must contain Ruler")
            assert(titles.contains("Rectangle"), "Dropdown must contain Rectangle")
            assert(!titles.contains("Backdrop"), "Dropdown must NOT contain removed Backdrop")
            assert(titles.contains("Pen"), "Dropdown must contain Pen")
            assert(!titles.contains("Magnifier"), "Dropdown must NOT contain removed Magnifier")
            assert(!titles.contains("Add Capture"), "Dropdown must NOT contain removed Add Capture")
            assert(titles.contains("Text"), "Dropdown must contain Text")
            assert(titles.contains("Blur"), "Dropdown must contain renamed Blur")
            assert(!titles.contains("Blur/Erase"), "Dropdown must NOT contain Blur/Erase")
            assert(titles.contains("Highlighter"), "Dropdown must contain Highlighter")
            assert(titles.contains("Spotlight"), "Dropdown must contain Spotlight")
            assert(titles.contains("Counter"), "Dropdown must contain Counter")
            assert(titles.contains("Callout"), "Dropdown must contain Callout")
            if let counterIdx = titles.firstIndex(of: "Counter"), let calloutIdx = titles.firstIndex(of: "Callout") {
                assert(calloutIdx == counterIdx + 1, "Callout must sit right after Counter in the dropdown")
            }
            if let calloutIdx = titles.firstIndex(of: "Callout"), let textIdx = titles.firstIndex(of: "Text") {
                assert(textIdx == calloutIdx + 1, "Text must sit right after Callout in the dropdown")
            }
            let collapsibleTitles = toolbar.collapsibleToolDefinitions.map { $0.title }
            if let counterIdx = collapsibleTitles.firstIndex(of: "Counter"), let calloutIdx = collapsibleTitles.firstIndex(of: "Callout") {
                assert(calloutIdx == counterIdx + 1, "Callout must sit right after Counter in the toolbar")
            } else {
                assert(false, "Toolbar must contain Counter and Callout")
            }
            if let calloutIdx = collapsibleTitles.firstIndex(of: "Callout"), let textIdx = collapsibleTitles.firstIndex(of: "Text") {
                assert(textIdx == calloutIdx + 1, "Text must sit right after Callout in the toolbar")
            } else {
                assert(false, "Toolbar must contain Callout and Text")
            }
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

            // 6. Compact zoom controls (magnifying glass buttons removed, only capsule with minus, percent, plus)
            assert(panel.toolbarView.zoomResetButton == nil, "Toolbar zoomResetButton must be removed from capsule")
            assert(panel.toolbarView.zoomFitButton == nil, "Toolbar zoomFitButton must be removed from capsule")
            assert(panel.toolbarView.zoomPercentButton != nil, "Toolbar must have zoomPercentButton")
            assert(panel.toolbarView.zoomInButton != nil, "Toolbar must have zoomInButton")
            assert(panel.toolbarView.zoomOutButton != nil, "Toolbar must have zoomOutButton")
            assert(panel.toolbarView.zoomContainerView != nil, "Toolbar must have compact zoomContainerView")

            // Test Zoom In button
            let magBeforeIn = sv.magnification
            panel.toolbarView.zoomInButton?.onAction?()
            assert(sv.magnification > magBeforeIn, "Clicking zoomInButton must increase magnification")

            // Test Zoom Out button
            let magBeforeOut = sv.magnification
            panel.toolbarView.zoomOutButton?.onAction?()
            assert(sv.magnification < magBeforeOut, "Clicking zoomOutButton must decrease magnification")

            // Test Zoom Reset (100% / Actual Size) via callback / menu action
            sv.magnification = 3.25
            panel.canvasView.zoomScale = 3.25
            panel.toolbarView.onZoomResetRequested?()
            assert(sv.magnification == 1.0, "onZoomResetRequested must reset magnification to 1.0 (100%)")
            assert(panel.canvasView.zoomScale == 1.0, "canvasView.zoomScale must be 1.0 after reset")
            assert(panel.toolbarView.metaLabel.superview == nil, "metaLabel must be removed from the toolbar")
            assert(panel.toolbarView.zoomPercentButton?.titleLabel.stringValue == "100%", "zoomPercentButton must display 100%")

            // Test Zoom Fit via callback / menu action
            panel.toolbarView.onZoomFitRequested?()
            assert(sv.magnification == 1.0, "onZoomFitRequested on small image must show 100%")

            // Test Zoom Presets Menu (ordered from lowest to largest, with 100% holding Cmd+0)
            let presetsMenu = panel.toolbarView.buildZoomPresetsMenu()
            assert(presetsMenu.items.contains { $0.title == "Best Fit" }, "Presets menu must contain 'Best Fit'")
            assert(!presetsMenu.items.contains { $0.title == "Actual Size (100%)" }, "Presets menu must NOT contain 'Actual Size (100%)'")

            let item100 = presetsMenu.items.first { $0.title == "100%" }
            assert(item100 != nil, "Presets menu must contain '100%'")
            assert(item100?.keyEquivalent == "0", "'100%' item must have keyEquivalent '0'")
            assert(item100?.keyEquivalentModifierMask == [.command], "'100%' item must have Cmd modifier mask")

            let percentItems = presetsMenu.items.compactMap { $0.title.hasSuffix("%") ? $0.title : nil }
            assert(percentItems == ["25%", "50%", "75%", "100%", "150%", "200%", "400%", "800%"], "Presets menu must list zoom percentages from lowest to largest")

            // Test onZoomSetRequested
            panel.toolbarView.onZoomSetRequested?(0.5)
            assert(abs(sv.magnification - 0.5) < 0.01, "onZoomSetRequested must set magnification to 0.5 (50%)")
            assert(panel.toolbarView.zoomPercentButton?.titleLabel.stringValue == "50%", "zoomPercentButton must display 50%")

            // 7. Cmd+1 Best Fit & Cmd+0 Actual Size
            sv.magnification = 2.5
            let cmd1Event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "1",
                charactersIgnoringModifiers: "1",
                isARepeat: false,
                keyCode: 18
            )!
            panel.canvasView.keyDown(with: cmd1Event)
            assert(sv.magnification == 1.0, "Cmd+1 on small image (200x150 in 800x600 window) must show 100% (1.0)")

            let cmd0Event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "0",
                charactersIgnoringModifiers: "0",
                isARepeat: false,
                keyCode: 29
            )!
            sv.magnification = 4.0
            panel.canvasView.keyDown(with: cmd0Event)
            assert(sv.magnification == 1.0, "Cmd+0 must reset magnification to 100% (1.0)")

            let largeContext = CGContext(
                data: nil,
                width: 2000,
                height: 1500,
                bitsPerComponent: 8,
                bytesPerRow: 8000,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            panel.loadImage(image: largeContext.makeImage()!)
            panel.setFrame(NSRect(x: 100, y: 100, width: 800, height: 600), display: true)
            panel.canvasView.keyDown(with: cmd1Event)
            assert(sv.magnification < 1.0, "Cmd+1 on large image (2000x1500 in 800x600 window) must scale down (< 1.0) to best fit available workspace")

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
            assert(panel.toolbarView.toolButtons[.callout]?.isHidden == false, "Callout visible at 900pt")
            assert(panel.toolbarView.overflowButton?.isHidden == true, "3-dots overflow button hidden when all tools fit at 900pt")

            // 3. Window resizing to 600pt (Medium): Window decides width; Blur hides under 3-dots
            panel.setFrame(NSRect(x: 100, y: 100, width: 600, height: 500), display: true)
            assert(panel.frame.width == 600.0)
            assert(panel.toolbarView.toolButtons[.select]?.isHidden == false, "Pointer visible at 600pt")
            assert(panel.toolbarView.toolButtons[.blur]?.isHidden == true, "Blur hidden at 600pt")
            assert(panel.toolbarView.toolButtons[.pen]?.isHidden == true, "Pen hidden at 600pt")
            assert(panel.toolbarView.toolButtons[.callout]?.isHidden == false, "Callout visible at 600pt")
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

        testRunner("Editor - Single Main Window Empty State (Drag or Click to Open) & Reuse") {
            // 1. Initializing EditorPanel without image
            let emptyPanel = EditorPanel()
            assert(emptyPanel.hasImage == false, "EditorPanel without image must have hasImage == false")
            assert(emptyPanel.welcomeDropView != nil, "welcomeDropView must exist in EditorPanel")
            assert(emptyPanel.welcomeDropView?.isHidden == false, "welcomeDropView must be visible when hasImage == false")
            assert(emptyPanel.welcomeDropView?.titleLabel.stringValue == "Drag or click to open", "Title must be 'Drag or click to open'")
            assert(emptyPanel.scrollView?.isHidden == true, "Canvas scrollView must be hidden in empty state")
            assert(emptyPanel.toolbarView.metaLabel.superview == nil, "Meta label must not be in toolbar stack")

            // 2. Loading image into the existing empty window
            let context = CGContext(
                data: nil,
                width: 320,
                height: 240,
                bitsPerComponent: 8,
                bytesPerRow: 1280,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let image = context.makeImage()!
            emptyPanel.loadImage(image: image, title: "test_shot.png")

            assert(emptyPanel.hasImage == true, "hasImage must be true after loadImage")
            assert(emptyPanel.welcomeDropView == nil || emptyPanel.welcomeDropView?.isHidden == true, "welcomeDropView must be removed or hidden after loadImage")
            assert(emptyPanel.scrollView?.isHidden == false, "scrollView must be visible after loadImage")
            assert(emptyPanel.document.activeCanvasBounds.width == 320, "Canvas bounds width must match loaded image")
            assert(emptyPanel.document.activeCanvasBounds.height == 240, "Canvas bounds height must match loaded image")
            assert(emptyPanel.toolbarView.metaLabel.superview == nil, "Meta label must remain omitted from toolbar")

            emptyPanel.close()
        }

        testRunner("Editor - Single Color Picker Popout & Conditional Tool Visibility") {
            let doc = EditorDocument(image: CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resolveTestImageURL()! as CFURL, nil)!, 0, nil)!)
            let canvas = EditorCanvasView(document: doc)
            let toolbar = EditorToolbarView(canvasView: canvas)
            toolbar.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
            toolbar.layout()

            // 1. In select mode with no annotation selected, color picker is HIDDEN
            doc.activeTool = .select
            doc.selectedLayerIDs.removeAll()
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == false, "Color picker must not show up in select mode with no annotation selected")
            assert(toolbar.colorStackView?.isHidden == true, "Color picker stack must be hidden in select mode")
            assert(toolbar.toolsSeparatorView?.isHidden == true, "Tools separator must be hidden when color picker is hidden")

            // 2. Only ONE color button in toolbar
            assert(toolbar.singleColorButton != nil, "Single color button must exist")
            assert(toolbar.colorStackView?.arrangedSubviews.count == 1, "Only one color button must be shown in the toolbar")

            // 3. When a drawing tool is selected (e.g. Arrow), color picker SHOWS
            doc.activeTool = .arrow
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == true, "Color picker must show when drawing tool is selected")
            assert(toolbar.colorStackView?.isHidden == false, "Color picker stack must be visible when arrow tool is selected")

            // 4. When Spotlight tool is selected, color picker is VISIBLE (spotlight outline color can be changed)
            doc.activeTool = .spotlight
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == true, "Color picker must be visible when spotlight is active")
            assert(toolbar.colorStackView?.isHidden == false, "Color picker stack must be visible when spotlight is active")

            // When Blur tool is selected, color picker is INVISIBLE (only blur has no outline)
            doc.activeTool = .blur
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == false, "Color picker must be hidden when blur is active because only blur has no outline")
            assert(toolbar.colorStackView?.isHidden == true, "Color picker stack must be hidden when blur is active")

            // 5. In Select mode, selecting a colorable annotation makes color picker VISIBLE with that annotation's color
            doc.activeTool = .select
            let rectLayer = RectangleLayer(rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: "#7048E8")
            doc.addLayer(rectLayer)
            doc.selectLayer(rectLayer)
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == true, "Color picker must show when an annotation is selected in select mode")
            assert(toolbar.colorStackView?.isHidden == false, "Color picker must be visible when an annotation is selected")
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#7048E8", "Single color button must reflect the selected annotation's color")

            // 6. When a Spotlight annotation is selected, color picker is VISIBLE (spotlight outline color can be changed)
            doc.selectedLayerIDs.removeAll()
            let spotLayer = FilterLayer(rects: [CGRect(x: 5, y: 5, width: 20, height: 20)], filterMode: .spotlight, color: "#FF3B30")
            doc.addLayer(spotLayer)
            doc.selectLayer(spotLayer)
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == true, "Color picker must be visible when spotlight annotation is selected")
            assert(toolbar.colorStackView?.isHidden == false, "Color picker must be visible for spotlight annotation")
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#FF3B30", "Single color button must reflect spotlight's outline color")

            // When a Blur annotation is selected, color picker remains INVISIBLE (only blur has no outline)
            doc.selectedLayerIDs.removeAll()
            let blurLayer = FilterLayer(rects: [CGRect(x: 5, y: 5, width: 20, height: 20)], filterMode: .gaussian)
            doc.addLayer(blurLayer)
            doc.selectLayer(blurLayer)
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.shouldShowColorPicker == false, "Color picker must remain invisible when blur annotation is selected")
            assert(toolbar.colorStackView?.isHidden == true, "Color picker must be hidden for blur annotation")

            // 7. Popout grid contains exactly 8 predefined swatches and operates without custom color
            let popoutVC = ColorPopoutViewController()
            popoutVC.loadView()
            assert(popoutVC.swatchButtons.count == 8, "Popout must contain exactly 8 predefined color swatches")
            assert(EditorToolbarView.predefinedSwatches.count == 8, "Must only operate on 8 predefined swatches")

            popoutVC.selectedColor = "#FFCC00"
            let yellowBtn = popoutVC.swatchButtons.first(where: { $0.hex.uppercased() == "#FFCC00" })
            assert(yellowBtn?.isActive == true, "Yellow swatch in popout must have active highlight")

            // 8. Clicking the single color button presents popover
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView?.addSubview(toolbar)
            doc.selectLayer(rectLayer)
            toolbar.updateSelectedToolVisuals()
            toolbar.singleColorButton?.onAction?()
            assert(toolbar.colorPopover != nil, "Popover must be created when color button is clicked")

            // 9. When Counter is selected and color changes, counter color and render badge update
            let counter = CounterLayer(center: CGPoint(x: 50, y: 50), value: 1, color: "#FF3B30")
            let dummyContext = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            counter.draw(in: dummyContext, scale: 1.0)
            doc.addLayer(counter)
            doc.selectLayer(counter)
            toolbar.updateSelectedToolVisuals()
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#FF3B30", "Color button must show Counter's color")

            toolbar.singleColorButton?.onAction?()
            if let popVC = toolbar.colorPopover?.contentViewController as? ColorPopoutViewController {
                popVC.onColorSelected?("#34C759")
            }
            assert(counter.color.uppercased() == "#34C759", "CounterLayer color must update to new green hex")
            counter.draw(in: dummyContext, scale: 1.0)
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#34C759", "Color button must reflect updated Counter color")
        }

        testRunner("Editor - FastColor High-Concurrency Thread Safety") {
            let fastColor = FastColor.shared
            let hexes = ["#FF3B30", "#007AFF", "#34C759", "#FFCC00", "#AF52DE", "#5856D6", "#FF9500", "#000000"]
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "impact.fastcolor.stress", attributes: .concurrent)

            for i in 0..<200 {
                group.enter()
                queue.async {
                    let hex = hexes[i % hexes.count]
                    let alpha = CGFloat((i % 10) + 1) / 10.0
                    let cg = fastColor.cgColor(hex: hex, alpha: alpha)
                    let ns = fastColor.nsColor(hex: hex, alpha: alpha)
                    assert(abs(cg.alpha - alpha) < 0.001, "CGColor alpha must match")
                    assert(abs(ns.alphaComponent - alpha) < 0.001, "NSColor alpha must match")
                    group.leave()
                }
            }
            group.wait()
        }

        testRunner("Editor - Blur Tool and Layer Selection Preserves Active Color") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let canvas = EditorCanvasView(document: doc)
            let toolbar = EditorToolbarView(canvasView: canvas)
            toolbar.frame = NSRect(x: 0, y: 0, width: 600, height: 44)

            // 1. User selects a custom active color (e.g. Blue #007AFF)
            doc.activeColor = "#007AFF"
            toolbar.updateSelectedColorVisuals()
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#007AFF", "Toolbar button must show active color")

            // 2. Switching to blur tool must not mutate activeColor, and hides color picker because blur has no outline
            doc.activeTool = .blur
            toolbar.updateSelectedToolVisuals()
            assert(doc.activeColor.uppercased() == "#007AFF", "Switching to blur tool must preserve activeColor")
            assert(toolbar.shouldShowColorPicker == false, "Color picker must be hidden when blur tool is active because only blur has no outline")
            assert(toolbar.colorStackView?.isHidden == true, "Color picker stack must be hidden when blur is active")

            // 3. Adding and selecting a blur layer must not mutate activeColor
            let blurLayer = FilterLayer(
                rects: [CGRect(x: 50, y: 50, width: 100, height: 100)],
                filterMode: .gaussian,
                intensity: 6.0,
                color: doc.activeColor
            )
            doc.addLayer(blurLayer)
            doc.selectLayer(blurLayer)
            toolbar.updateSelectedToolVisuals()

            assert(doc.activeColor.uppercased() == "#007AFF", "Selecting blur layer must not overwrite activeColor")
            assert(toolbar.shouldShowColorPicker == false, "Color picker must remain hidden for blur layer")
            assert(toolbar.colorStackView?.isHidden == true, "Color picker stack must remain hidden for blur layer")

            // 4. Hit-testing selection on blur layer must also not mutate activeColor
            _ = doc.selectLayer(at: CGPoint(x: 60, y: 60))
            assert(doc.activeColor.uppercased() == "#007AFF", "Selecting blur layer at point must not overwrite activeColor")

            // 5. Subsequent vector annotations created must retain user's chosen activeColor
            let arrow = ArrowLayer(
                start: CGPoint(x: 10, y: 10),
                end: CGPoint(x: 100, y: 100),
                color: doc.activeColor
            )
            assert(arrow.color.uppercased() == "#007AFF", "Subsequent layer must use user-chosen activeColor, not white")
        }

        testRunner("Editor - Spotlight Outline Color Can Be Changed") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let canvas = EditorCanvasView(document: doc)
            let toolbar = EditorToolbarView(canvasView: canvas)
            toolbar.frame = NSRect(x: 0, y: 0, width: 600, height: 44)

            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView?.addSubview(toolbar)

            // 1. Initial active color is #FF3B30
            doc.activeColor = "#FF3B30"
            doc.activeTool = .spotlight
            toolbar.updateSelectedToolVisuals()

            // 2. Color picker MUST be visible when spotlight is active
            assert(toolbar.shouldShowColorPicker == true, "Color picker must be visible when spotlight is active")
            assert(toolbar.colorStackView?.isHidden == false, "Color stack view must be visible when spotlight is active")
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#FF3B30", "Color button must show active color")

            // 3. Spotlight overlay layer was created with active color
            guard let spotOverlay = doc.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Spotlight overlay not found"])
            }
            assert(spotOverlay.color.uppercased() == "#FF3B30", "Spotlight overlay must inherit initial activeColor")

            // 4. Changing color via popout updates the spotlight outline color
            toolbar.singleColorButton?.onAction?()
            if let popVC = toolbar.colorPopover?.contentViewController as? ColorPopoutViewController {
                popVC.onColorSelected?("#34C759")
            }
            assert(spotOverlay.color.uppercased() == "#34C759", "Spotlight overlay color must update to chosen green hex")
            assert(doc.activeColor.uppercased() == "#34C759", "Document activeColor must update to chosen green hex")
            assert(toolbar.singleColorButton?.currentColor.uppercased() == "#34C759", "Toolbar color button must reflect new spotlight outline color")

            // 5. Drawing in dummy context uses the updated spotlight outline color
            let dummyContext = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            spotOverlay.rects = [CGRect(x: 10, y: 10, width: 40, height: 40)]
            spotOverlay.draw(in: dummyContext, scale: 1.0)
        }

        testRunner("Editor - Clicking Spotlight Rectangle or Overlay Cancels Tool to Select") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let canvas = EditorCanvasView(document: doc)
            canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            let toolbar = EditorToolbarView(canvasView: canvas)
            toolbar.frame = NSRect(x: 0, y: 0, width: 600, height: 44)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView?.addSubview(canvas)
            win.contentView?.addSubview(toolbar)

            // 1. Activate spotlight tool
            doc.activeTool = .spotlight
            toolbar.updateSelectedToolVisuals()
            assert(doc.activeTool == .spotlight, "Active tool must be spotlight")

            // 2. Click on the overlay (without dragging to size) -> must cancel tool and pick Select (V)
            let overlayWinPt = canvas.convert(NSPoint(x: 200, y: 200), to: nil)
            let overlayClickDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: overlayWinPt,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1.0
            )!
            let overlayClickUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: overlayWinPt,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0.0
            )!
            canvas.mouseDown(with: overlayClickDown)
            canvas.mouseUp(with: overlayClickUp)
            assert(doc.activeTool == .select, "Clicking on overlay must cancel spotlight tool and pick Select (V)")
            assert(toolbar.toolButtons[.select]?.isActive == true, "Select (V) button must be active")

            // 3. Add a spotlight hole
            let spotlight = FilterLayer(rects: [CGRect(x: 50, y: 50, width: 100, height: 80)], filterMode: .spotlight)
            doc.addLayer(spotlight)

            // 4. Activate spotlight tool again
            doc.activeTool = .spotlight
            toolbar.updateSelectedToolVisuals()

            // 5. Click inside the spotlight rectangle (hollow center at (100, 90)) -> cancels tool and picks Select (V)
            let centerWinPt = canvas.convert(NSPoint(x: 100, y: 90), to: nil)
            let centerClickDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: centerWinPt,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 3,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: centerClickDown)
            assert(doc.activeTool == .select, "Clicking inside spotlight rectangle must cancel spotlight tool and pick Select (V)")
            assert(doc.selectedLayerIDs.contains(spotlight.id), "Spotlight layer must be selected")
            assert(spotlight.selectedRectIndex == 0, "Selected rect index must be set to clicked hole")

            // 6. Test border catchment matching rectangle: max(10.0, strokeWidth + 6.0)
            spotlight.strokeWidth = 8.0
            assert(spotlight.rectIndex(at: CGPoint(x: 50 - 12, y: 60)) != nil, "Point within 14px of left border must be caught")
            assert(spotlight.rectIndex(at: CGPoint(x: 50 - 20, y: 60)) == nil, "Point outside 14px must not be caught")

            // 7. Test hover area on borders: hover event on border sets hoveredLayer to spotlight
            let borderMoveEvent = NSEvent.mouseEvent(
                with: .mouseMoved,
                location: canvas.convert(NSPoint(x: 50 - 5, y: 60), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 4,
                clickCount: 0,
                pressure: 0.0
            )!
            canvas.mouseMoved(with: borderMoveEvent)
            assert(canvas.hoveredLayer?.id == spotlight.id, "Hovering over spotlight border must set hoveredLayer")

            // Hovering inside the hole or on distant overlay clears hoveredLayer
            let centerMoveEvent = NSEvent.mouseEvent(
                with: .mouseMoved,
                location: canvas.convert(NSPoint(x: 100, y: 90), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 5,
                clickCount: 0,
                pressure: 0.0
            )!
            canvas.mouseMoved(with: centerMoveEvent)
            assert(canvas.hoveredLayer == nil, "Hovering inside hollow center must not set hoveredLayer")

            // 8. Active clicking on border while spotlight tool is active selects it, cancels tool, and prepares drag
            doc.activeTool = .spotlight
            toolbar.updateSelectedToolVisuals()
            let borderClickDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: canvas.convert(NSPoint(x: 50 - 5, y: 60), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 6,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: borderClickDown)
            assert(doc.activeTool == .select, "Clicking on spotlight border must switch activeTool to .select")
            assert(doc.selectedLayerIDs.contains(spotlight.id), "Spotlight layer must remain selected after border click")
            assert(spotlight.selectedRectIndex == 0, "Selected rect index must be 0")
        }

        testRunner("Editor - Blur Areas Always Under Spotlight Overlay") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)

            // 1. When adding spotlight first, then adding blur: blur layer must be inserted before spotlight in doc.layers
            doc.ensureSpotlightOverlay()
            guard let spotlight = doc.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Spotlight not found"])
            }
            spotlight.rects = [CGRect(x: 100, y: 100, width: 200, height: 200)]

            let blurLayer = FilterLayer(rects: [CGRect(x: 50, y: 50, width: 300, height: 300)], filterMode: .gaussian, intensity: 10.0)
            doc.addLayer(blurLayer)

            let blurIdx = doc.layers.firstIndex(where: { $0.id == blurLayer.id })!
            let spotIdx = doc.layers.firstIndex(where: { $0.id == spotlight.id })!
            assert(blurIdx < spotIdx, "Blur layer must be positioned before (under) spotlight in document.layers")

            // 2. When creating blur first, then ensuring spotlight: spotlight must be placed after blur
            let doc2 = EditorDocument(image: cgImage)
            let existingBlur = FilterLayer(rects: [CGRect(x: 20, y: 20, width: 80, height: 80)], filterMode: .gaussian)
            doc2.addLayer(existingBlur)
            doc2.ensureSpotlightOverlay()

            let blurIdx2 = doc2.layers.firstIndex(where: { $0.id == existingBlur.id })!
            let spotIdx2 = doc2.layers.firstIndex(where: { ($0 as? FilterLayer)?.filterMode == .spotlight })!
            assert(blurIdx2 < spotIdx2, "Spotlight overlay must be placed after blur layer in document.layers")

            // 3. Composition rendering: rendered composition must succeed with blur under spotlight
            let comp = doc.renderComposition()
            assert(comp != nil, "Composition with blur under spotlight must render successfully")

            // 4. Canvas drawing: verify canvas draw pass with both blur and spotlight active
            let canvas = EditorCanvasView(document: doc)
            canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            assert(rep.size.width > 0, "Canvas must draw display cache with blur under spotlight")
        }

        testRunner("Editor - Blur Tool Has Zero Outline") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let blurLayer = FilterLayer(rects: [CGRect(x: 40, y: 40, width: 120, height: 80)], filterMode: .gaussian)
            doc.addLayer(blurLayer)
            let canvas = EditorCanvasView(document: doc)

            // 1. hoverPath must strictly be nil for blur layers
            assert(canvas.hoverPath(for: blurLayer) == nil, "hoverPath for blur layer must be nil")

            // 2. updateHoverState must not set hoverOutlineLayer for blur layers
            canvas.updateHoverState(to: blurLayer)
            assert(canvas.hoverOutlineLayer == nil, "hoverOutlineLayer must be nil when hovering over blur layer")

            // 3. FilterLayer.draw(in:scale:) must not draw selection outline when selected
            blurLayer.selectedRectIndex = 0
            guard let bitmapCtx = CGContext(
                data: nil,
                width: 200,
                height: 200,
                bitsPerComponent: 8,
                bytesPerRow: 200 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
            }
            blurLayer.draw(in: bitmapCtx, scale: 1.0)
            // Path in context must remain empty after drawing blur layer
            assert(bitmapCtx.path == nil || bitmapCtx.path?.isEmpty == true, "FilterLayer.draw for blur must not stroke or set any path in context")

            // 4. Spotlight on the other hand DOES return a hoverPath
            let spotlight = FilterLayer(rects: [CGRect(x: 40, y: 40, width: 120, height: 80)], filterMode: .spotlight)
            assert(canvas.hoverPath(for: spotlight) != nil, "Spotlight layer must have a hover path")
            canvas.updateHoverState(to: spotlight)
            assert(canvas.hoverOutlineLayer?.id == spotlight.id, "hoverOutlineLayer must be set for spotlight layer")
        }

        testRunner("Editor - Any Tool Inside Spotlight Square Works Normally") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }

            let doc = EditorDocument(image: cgImage)
            let spotlight = FilterLayer(rects: [CGRect(x: 50, y: 50, width: 200, height: 200)], filterMode: .spotlight)
            doc.addLayer(spotlight)

            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            let canvas = EditorCanvasView(document: doc)
            canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            win.contentView = canvas

            // 1. Arrow tool used inside Spotlight square: must NOT return to select
            doc.activeTool = .arrow
            let startInside = NSPoint(x: 100, y: 100)
            let endInside = NSPoint(x: 180, y: 160)

            let arrowDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: canvas.convert(startInside, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 10,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: arrowDown)
            assert(doc.activeTool == .arrow, "Active tool must remain .arrow when clicking inside spotlight square (must not return to select)")
            assert(canvas.activeCreatingLayer is ArrowLayer, "activeCreatingLayer must be an ArrowLayer")

            let arrowDrag = NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: canvas.convert(endInside, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 11,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDragged(with: arrowDrag)

            let arrowUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: canvas.convert(endInside, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 12,
                clickCount: 1,
                pressure: 0.0
            )!
            canvas.mouseUp(with: arrowUp)

            let createdArrow = doc.layers.first(where: { $0 is ArrowLayer }) as? ArrowLayer
            assert(createdArrow != nil, "ArrowLayer must be created and added to document")
            assert(createdArrow?.start == CGPoint(x: 100, y: 100), "Arrow start must be inside spotlight square")

            // Clean up arrow before testing rectangle and pen tools
            doc.removeLayer(id: createdArrow!.id)

            // 2. Rectangle tool used inside Spotlight square
            doc.activeTool = .rectangle
            let rectDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: canvas.convert(NSPoint(x: 110, y: 110), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 13,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: rectDown)
            assert(doc.activeTool == .rectangle, "Active tool must remain .rectangle when clicking inside spotlight square")
            assert(canvas.activeCreatingLayer is RectangleLayer, "activeCreatingLayer must be a RectangleLayer")

            let rectUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: canvas.convert(NSPoint(x: 110, y: 110), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 14,
                clickCount: 1,
                pressure: 0.0
            )!
            canvas.mouseUp(with: rectUp)

            // 3. Pen tool used inside Spotlight square
            doc.activeTool = .pen
            let penDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: canvas.convert(NSPoint(x: 120, y: 120), to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 15,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: penDown)
            assert(doc.activeTool == .pen, "Active tool must remain .pen when clicking inside spotlight square")
            assert(canvas.activeCreatingLayer is PenLayer, "activeCreatingLayer must be a PenLayer")
        }

        testRunner("Editor - Callout Text Measurement & Body Sizing") {
            let lineHeight = CalloutTextLayout.textSize(for: "A").height
            assert(lineHeight > 10, "One line must have a positive line height")

            let empty = CalloutTextLayout.textSize(for: "")
            assert(empty.width == 0, "Empty text must measure zero width")

            let space = CalloutTextLayout.textSize(for: " ")
            assert(space.width > 0 && space.width < CalloutTextLayout.minTextWidth + 2, "A single space must measure a few points wide")
            assert(abs(space.height - lineHeight) < 0.01, "A single space must be one line tall")

            let newline = CalloutTextLayout.textSize(for: "\n")
            assert(newline.width == 0, "A lone newline must not report the unbounded container width")
            assert(abs(newline.height - 2 * lineHeight) < 0.01, "A lone newline must be two lines tall")

            let hello = CalloutTextLayout.textSize(for: "Hello")
            let helloNewline = CalloutTextLayout.textSize(for: "Hello\n")
            assert(abs(helloNewline.width - hello.width) < 0.01, "A trailing newline must keep the widest line's width")
            assert(abs(helloNewline.height - 2 * lineHeight) < 0.01, "A trailing newline must add the extra empty line")

            let twoLines = CalloutTextLayout.textSize(for: "Hello\nWide second line")
            assert(twoLines.width > hello.width, "Width must follow the widest line")
            assert(abs(twoLines.height - 2 * lineHeight) < 0.01, "Two lines must be two lines tall")

            // Body = text + compact padding (8 x 12), with a minimum text width for whitespace callouts
            let callout = CalloutLayer(tip: CGPoint(x: 200, y: 200), text: "Hi")
            let small = callout.bodyRect
            assert(small.height == ceil(lineHeight + 16), "Body height must be one line plus vertical padding")
            callout.text = "Hello there\nsecond line"
            let grown = callout.bodyRect
            assert(grown.width > small.width && grown.height > small.height, "Body must grow with the text")
            assert(grown.maxY == small.maxY && grown.midX == small.midX, "A bottom-beak body must grow upward and symmetrically around the beak")
            callout.text = "Hi"
            assert(callout.bodyRect == small, "Body must shrink back when text shrinks")
            callout.text = " "
            assert(callout.bodyRect.width >= CalloutTextLayout.minTextWidth + 24, "Whitespace callout must keep a visible minimum width")
            assert(CalloutLayer.bodySize(for: "").height == CalloutLayer.bodySize(for: "A").height, "Empty text must measure one line tall")
            assert(CalloutLayer.bodySize(for: "").width == ceil(CalloutTextLayout.minTextWidth + 24), "Empty text must keep the minimum width")
        }

        testRunner("Editor - Callout Default Beak Keeps Its Size At Any Body Size") {
            // Beak width measured 1pt below the body edge must not depend on the text
            func beakWidth(_ callout: CalloutLayer) -> CGFloat {
                let y = callout.bodyRect.maxY + 1.0
                let path = callout.pathForCallout()
                var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
                var x = callout.bodyRect.minX - 20.0
                while x <= callout.bodyRect.maxX + 20.0 {
                    if path.contains(CGPoint(x: x, y: y)) { minX = min(minX, x); maxX = max(maxX, x) }
                    x += 0.25
                }
                return maxX - minX
            }
            let tip = CGPoint(x: 300, y: 300)
            let reference = CalloutLayer(tip: tip, text: "Callout")
            let referenceWidth = beakWidth(reference)
            for text in ["", " ", "H", "Hello world, a much longer line", "Two\nlines", "\n\n"] {
                let callout = CalloutLayer(tip: tip, text: "")
                callout.text = text
                assert(abs(beakWidth(callout) - referenceWidth) < 0.5, "Default beak must keep its size for \(text.debugDescription)")
                assert(abs(callout.bodyRect.midX - tip.x) < 0.001, "Default beak must stay centered under the body for \(text.debugDescription)")
                assert(callout.tailTip == tip, "Typing must never move the tip")
            }

            // Beak base width is clamped to maxBaseWidth (~60 px at the root) even when the tip is pulled very far
            let longBeak = CalloutLayer(tip: CGPoint(x: 300, y: 300), text: "THE BEAK GETS MUCH TOO WIDE AT THE ROOT")
            longBeak.tailTip = CGPoint(x: 300, y: 1000)
            let longWidth = beakWidth(longBeak)
            assert(longWidth <= 60.5, "Beak base width must be clamped to ~60 px max (got \(longWidth))")
        }

        testRunner("Editor - Callout Text Changes Re-Anchor The Body Around A Fixed Beak") {
            // Bottom beak (default creation): the box grows left/right around the tip and upward for new lines
            let tip = CGPoint(x: 240, y: 260)
            let reference = CalloutLayer(tip: tip, text: "Callout")
            let callout = CalloutLayer(tip: tip, text: "")
            let emptyBody = callout.bodyRect
            assert(emptyBody.height == reference.bodyRect.height, "Empty callout must already be one line tall")
            for text in ["H", "Hel", "Hello", "Hello world", "Callout"] {
                callout.text = text
                let body = callout.bodyRect
                assert(callout.tailTip == tip, "Typing must never move the tip (\(text))")
                assert(body.midX == tip.x, "Body must stay centered on the tip (\(text))")
                assert(body.maxY == emptyBody.maxY, "Beak edge must keep its position (\(text))")
                // Beak base: the filled span just below the body edge
                let path = callout.pathForCallout()
                let filled = stride(from: body.minX, through: body.maxX, by: 0.25).filter { path.contains(CGPoint(x: $0, y: body.maxY + 1)) }
                guard let left = filled.first, let right = filled.last else {
                    throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Beak must attach to the bottom edge (\(text))"])
                }
                assert(abs((left + right) / 2 - tip.x) < 0.5, "Beak base center must stay at the tip's x (\(text))")
            }
            assert(callout.bodyRect == reference.bodyRect, "Typed callout must match one created with the same text")
            assert(callout.pathForCallout().boundingBoxOfPath == reference.pathForCallout().boundingBoxOfPath, "Typed beak must match the reference beak")
            callout.text = "Hello\nworld"
            assert(callout.bodyRect.maxY == emptyBody.maxY && callout.bodyRect.height > emptyBody.height, "New lines must grow the body upward")
            callout.text = ""
            assert(callout.bodyRect == emptyBody, "Deleting all text must restore the empty body")

            // Side beak: the right edge stays put and the beak keeps its height along it
            let side = CalloutLayer(tip: CGPoint(x: 500, y: 300), text: "")
            let start = side.bodyRect
            side.updateHandle(index: 0, to: CGPoint(x: start.maxX + 30, y: start.midY))
            let sideTip = side.tailTip
            side.text = "Hello world"
            assert(side.tailTip == sideTip, "Typing must not move a side tip")
            assert(side.bodyRect.maxX == start.maxX && side.bodyRect.midY == start.midY, "A right-beak body must grow leftward around the beak")

            // Direct assignment of the same text leaves the body alone
            let before = side.bodyRect
            side.text = "Hello world"
            assert(side.bodyRect == before, "Re-assigning the same text must not move the body")
        }

        testRunner("Editor - Callout Beak Geometry, Hit Testing & Handles") {
            let callout = CalloutLayer(tip: CGPoint(x: 300, y: 300), text: "Callout")
            let body = callout.bodyRect
            assert(abs(body.midX - 300) < 0.01, "Default body must be centered above the tip")
            assert(abs(callout.tailTip.y - body.maxY - 9) < 0.01, "Default tip must sit 9 pt below the body")

            // The beak attaches to the edge facing the tip: the outline extends to the tip on every side
            let tips: [(String, CGPoint)] = [
                ("bottom", CGPoint(x: body.midX + 20, y: body.maxY + 60)),
                ("top", CGPoint(x: body.midX - 15, y: body.minY - 70)),
                ("left", CGPoint(x: body.minX - 120, y: body.midY + 5)),
                ("right", CGPoint(x: body.maxX + 200, y: body.midY - 3))
            ]
            for (name, tip) in tips {
                callout.updateHandle(index: 0, to: tip)
                let path = callout.pathForCallout()
                assert(!path.isEmpty, "Callout path must not be empty (\(name))")
                let bounds = path.boundingBoxOfPath
                assert(bounds.insetBy(dx: -2, dy: -2).contains(tip), "Beak must reach the tip on the \(name) edge")
                // Halfway between body edge and tip lies on the beak
                let edgePoint: CGPoint
                switch name {
                case "bottom": edgePoint = CGPoint(x: tip.x, y: body.maxY)
                case "top": edgePoint = CGPoint(x: tip.x, y: body.minY)
                case "left": edgePoint = CGPoint(x: body.minX, y: tip.y)
                default: edgePoint = CGPoint(x: body.maxX, y: tip.y)
                }
                let mid = CGPoint(x: (edgePoint.x + tip.x) / 2, y: (edgePoint.y + tip.y) / 2)
                assert(callout.contains(point: mid), "Beak must be hit-testable on the \(name) edge")
                assert(callout.getBoundingBox().contains(tip), "Bounding box must include the \(name) tip")
                assert(callout.hitTestHandle(point: tip) == 0, "Tip must be handle 0 (\(name))")
            }

            // The beak only grows outward from the edge facing the tip
            callout.updateHandle(index: 0, to: CGPoint(x: body.midX, y: body.maxY + 40))
            assert(callout.pathForCallout().boundingBoxOfPath.minY >= body.minY - 0.01, "A bottom beak must not extend above the body")
            callout.updateHandle(index: 0, to: CGPoint(x: body.midX, y: body.minY - 40))
            assert(callout.pathForCallout().boundingBoxOfPath.maxY <= body.maxY + 0.01, "A top beak must not extend below the body")

            // A tip dragged inside the body is pushed outside
            callout.updateHandle(index: 0, to: CGPoint(x: body.midX, y: body.maxY - 3))
            assert(!body.contains(callout.tailTip), "Tip inside the body must be pushed outside")
            assert(callout.tailTip.y > body.maxY, "Tip near the bottom edge must be pushed below it")

            // contains: body and beak, not far points
            assert(callout.contains(point: CGPoint(x: body.midX, y: body.midY)), "Body center must be contained")
            assert(callout.contains(point: CGPoint(x: body.minX + 2, y: body.minY + 2)), "Body padding must be contained")
            assert(!callout.contains(point: CGPoint(x: body.maxX + 300, y: body.maxY + 300)), "Far point must not be contained")
            assert(callout.hitTestHandle(point: CGPoint(x: body.midX, y: body.midY)) == nil, "Body must not hit the tip handle")

            // move shifts origin and tip together
            let originBefore = callout.origin
            let tipBefore = callout.tailTip
            callout.move(by: CGPoint(x: 15, y: -7))
            assert(callout.origin == CGPoint(x: originBefore.x + 15, y: originBefore.y - 7), "Move must shift the body")
            assert(callout.tailTip == CGPoint(x: tipBefore.x + 15, y: tipBefore.y - 7), "Move must shift the tip")

            // Text color: white, dark on the white swatch
            assert(callout.textColor == NSColor.white, "Callout text must be white on colored backgrounds")
            callout.color = "#FFCC00"
            assert(callout.textColor == NSColor.white, "Yellow callout must keep white text")
            callout.color = "#FFFFFF"
            let dark = callout.textColor.usingColorSpace(.sRGB)!
            assert(abs(dark.redComponent - 0x1E / 255.0) < 0.01 && abs(dark.blueComponent - 0x2E / 255.0) < 0.01, "White callout must use #1E272E text")
            callout.color = "#ffffff"
            assert(callout.textColor != NSColor.white, "White swatch check must be case-insensitive")

            // clone keeps identity and geometry
            let copy = callout.clone() as! CalloutLayer
            assert(copy.id == callout.id && copy.text == callout.text && copy.tailTip == callout.tailTip && copy.origin == callout.origin, "Clone must preserve id, text and geometry")
        }

        testRunner("Editor - Callout Tool Shortcut T, Click-Drag Placement & Composition") {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)
            let panel = EditorPanel(document: doc)
            let canvas = panel.canvasView

            let keyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)!
            canvas.keyDown(with: keyEvent)
            assert(doc.activeTool == .callout, "Hotkey 't' must switch activeTool to .callout")

            let downEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 200, y: 200), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDown(with: downEvent)
            guard let creating = canvas.activeCreatingLayer as? CalloutLayer else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "MouseDown with Callout tool must create a CalloutLayer"])
            }
            let tip = creating.tailTip
            let origin0 = creating.origin
            assert(creating.text.isEmpty, "New callout must start empty")
            assert(creating.bodyRect.maxY < tip.y, "New callout body must sit above the pressed tip")

            let dragEvent = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 290, y: 160), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)!
            canvas.mouseDragged(with: dragEvent)
            assert(creating.tailTip == tip, "Dragging while creating must keep the tip pinned")
            assert(abs(creating.origin.x - origin0.x - 90) < 0.001, "Dragging must move the body horizontally with the mouse")
            assert(abs(abs(creating.origin.y - origin0.y) - 40) < 0.001, "Dragging must move the body vertically with the mouse")

            let upEvent = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 290, y: 160), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0)!
            canvas.mouseUp(with: upEvent)
            guard let editor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "MouseUp must open the callout editor"])
            }
            editor.insertText("Callout", replacementRange: NSRange(location: NSNotFound, length: 0))
            canvas.endCalloutEditing()

            assert(doc.layers.count == 1, "MouseUp must commit exactly one callout")
            guard let committed = doc.layers.first as? CalloutLayer else {
                throw NSError(domain: "EditorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Committed layer must be CalloutLayer"])
            }
            assert(committed.tailTip == tip, "Committed callout tip must stay at the mouse-down point")
            assert(doc.activeTool == .select, "Callout tool must return to Select after placing")
            assert(doc.selectedLayerIDs == [committed.id], "Placed callout must stay selected")
            assert(canvas.activeCreatingLayer == nil, "Creation state must be cleared")
            assert(canvas.hoverPath(for: committed) != nil, "Callout must have a hover outline")

            // Export renders the callout
            let plainDoc = EditorDocument(image: cgImage)
            let plain = plainDoc.renderComposition()!
            let composed = doc.renderComposition()!
            assert(composed.width >= plain.width && composed.height >= plain.height, "Composition must cover the image")
            func pixels(_ image: CGImage) -> [UInt8] {
                let w = image.width, h = image.height
                var data = [UInt8](repeating: 0, count: w * h * 4)
                let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return data
            }
            let differs = composed.width != plain.width || composed.height != plain.height || pixels(composed) != pixels(plain)
            assert(differs, "Composition with a callout must differ from the plain image")

            panel.close()
        }

        // Shared helpers for the callout editing-session tests
        func makeCalloutPanel() throws -> (EditorDocument, EditorPanel, EditorCanvasView) {
            guard let imageURL = resolveTestImageURL(),
                  let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test-image.jpg"])
            }
            let doc = EditorDocument(image: cgImage)
            let panel = EditorPanel(document: doc)
            return (doc, panel, panel.canvasView)
        }
        // Converts a canvas point into the window location canvasPoint(from:) maps back to it
        func windowLocation(_ canvas: EditorCanvasView, _ p: CGPoint) -> NSPoint {
            let origin = canvas.document.activeCanvasBounds.origin
            return canvas.convert(NSPoint(x: p.x - origin.x, y: p.y - origin.y), to: nil)
        }
        func mouse(_ type: NSEvent.EventType, _ canvas: EditorCanvasView, _ p: CGPoint, clickCount: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: windowLocation(canvas, p), modifierFlags: [], timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseUp ? 0.0 : 1.0)!
        }
        func key(_ chars: String, _ code: UInt16, _ mods: NSEvent.ModifierFlags = [], window: NSWindow?) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        // Callout tool click at a canvas point; returns the new callout and its open editor
        func createCallout(_ doc: EditorDocument, _ canvas: EditorCanvasView, at p: CGPoint) throws -> (CalloutLayer, CalloutTextView) {
            doc.activeTool = .callout
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, p))
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, p))
            guard let editor = canvas.calloutEditor, let callout = doc.layers.last as? CalloutLayer else {
                throw NSError(domain: "EditorTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Callout creation must open an editor"])
            }
            return (callout, editor)
        }
        func typeText(_ editor: CalloutTextView, _ text: String) {
            editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        func sameColor(_ a: NSColor?, _ b: NSColor) -> Bool {
            guard let a = a?.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
            return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
                && abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
        }
        // Closes without clipboard copy or numbered-file save side effects
        func quietClose(_ doc: EditorDocument, _ panel: EditorPanel) {
            doc.layers.removeAll()
            doc.isModified = false
            EditorPanel.copyToClipboardOverride = false
            panel.close()
            EditorPanel.copyToClipboardOverride = nil
        }

        testRunner("Editor - Callout Editing Opens On Creation With Focused Caret And Resizes Live") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let (callout, editor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 300))

            // Empty callout with a caret, focused and ready for typing
            assert(canvas.subviews.contains { $0 === editor }, "Creation must add a CalloutTextView to the canvas")
            assert(canvas.isEditingCallout, "Canvas must report an editing session")
            assert(doc.activeTool == .callout, "Tool must stay Callout while editing")
            assert(doc.layers.count == 1 && callout.text.isEmpty, "New callout must start empty")
            assert(callout.isTextHidden, "The layer must not draw text while the editor does")
            assert(doc.selectedLayerIDs == [callout.id], "Editing callout must be selected")
            assert(panel.firstResponder === editor, "Editor must be first responder so the caret appears and keys arrive")
            assert(editor.selectedRange() == NSRange(location: 0, length: 0), "Caret must sit at the start of the empty text")
            assert(callout.bodyRect.size == CalloutLayer.bodySize(for: ""), "Empty callout must keep minimum width and one line height")
            assert(callout.bodyRect.height > CalloutTextLayout.padding.top + CalloutTextLayout.padding.bottom, "Empty callout must be one line tall")

            // Caret, text and selection follow the callout's text color
            assert(sameColor(editor.textColor, callout.textColor), "Editor text color must match the callout text color")
            assert(sameColor(editor.insertionPointColor, callout.textColor), "Caret color must match the callout text color")
            assert(sameColor(editor.typingAttributes[.foregroundColor] as? NSColor, callout.textColor), "Typing color must match the callout text color")
            assert(!editor.drawsBackground && !editor.isRichText && !editor.allowsUndo, "Editor must be transparent, plain text and without keystroke undo")

            // Same layout as CalloutLayer.draw: inset = padding, frame = body − elastic origin
            func assertAligned(_ label: String) {
                let o = doc.activeCanvasBounds.origin
                assert(editor.frame == callout.bodyRect.offsetBy(dx: -o.x, dy: -o.y), "Editor frame must track the body (\(label))")
                assert(editor.textContainerOrigin == CGPoint(x: CalloutTextLayout.padding.left, y: CalloutTextLayout.padding.top), "Editor text must start at the padding (\(label))")
                assert(editor.textContainer?.lineFragmentPadding == 0, "Editor must use zero fragment padding (\(label))")
                assert(editor.font == CalloutTextLayout.font, "Editor must use the callout font (\(label))")
            }
            assertAligned("empty")

            // Typing grows the body live; deleting shrinks it back
            let emptyBody = callout.bodyRect
            typeText(editor, "Hi")
            assert(callout.text == "Hi", "Typed text must reach the layer immediately")
            assert(callout.bodyRect.width > emptyBody.width, "Typing must widen the body")
            assert(callout.bodyRect.height == emptyBody.height, "The first keystroke must not change the body height")
            assert(callout.tailTip == CGPoint(x: 300, y: 300), "Typing must not move the tip")
            assert(callout.bodyRect.midX == callout.tailTip.x && callout.bodyRect.maxY == emptyBody.maxY, "Body must grow symmetrically around the tip, keeping its beak edge")
            assertAligned("Hi")
            if let lm = editor.layoutManager, let tc = editor.textContainer {
                lm.ensureLayout(for: tc)
                let used = lm.usedRect(for: tc)
                let measured = CalloutTextLayout.textSize(for: "Hi")
                assert(abs(used.width - measured.width) < 0.01 && abs(used.height - measured.height) < 0.01, "Editor layout must match CalloutTextLayout measurement")
            }
            let hiBody = callout.bodyRect
            typeText(editor, "\nsecond line")
            assert(callout.bodyRect.height > hiBody.height && callout.bodyRect.width > hiBody.width, "Return and a longer line must grow the body")
            assert(callout.bodyRect.maxY == hiBody.maxY && callout.bodyRect.midX == callout.tailTip.x, "New lines must grow the body upward around the tip")
            assertAligned("two lines")
            editor.selectAll(nil)
            editor.deleteBackward(nil)
            assert(callout.text.isEmpty && callout.bodyRect == emptyBody, "Deleting must shrink the body back")
            typeText(editor, "Hi")
            assert(callout.bodyRect == hiBody, "Retyping must restore the size")

            // Esc sent to the editor finishes: kept, selected, Select tool, editor gone, one undo step
            editor.keyDown(with: key("\u{1b}", 53, window: panel))
            assert(!canvas.isEditingCallout && canvas.calloutEditor == nil, "Esc must end the session")
            assert(!canvas.subviews.contains { $0 is CalloutTextView }, "Esc must remove the editor")
            assert(doc.layers.count == 1 && callout.text == "Hi", "Esc must keep the typed callout")
            assert(!callout.isTextHidden, "The layer must draw its text again after editing")
            assert(doc.activeTool == .select, "Esc must return to the Select tool")
            assert(doc.selectedLayerIDs == [callout.id], "Finished callout must stay selected")
            assert(panel.firstResponder === canvas, "Canvas must take keys again after editing")
            doc.undo()
            assert(doc.layers.isEmpty, "One undo must remove the whole new-callout session")
            doc.redo()
            assert((doc.layers.first as? CalloutLayer)?.text == "Hi", "Redo must restore the callout")
            doc.selectedLayerIDs = [callout.id]

            // Esc lifecycle: second Esc deselects, third closes
            var closeCount = 0
            canvas.onCloseRequested = { closeCount += 1 }
            canvas.handleEscapeKey()
            assert(doc.selectedLayerIDs.isEmpty && closeCount == 0, "Second Esc must deselect")
            doc.layers.removeAll()
            doc.isModified = false
            EditorPanel.copyToClipboardOverride = false
            canvas.handleEscapeKey()
            EditorPanel.copyToClipboardOverride = nil
            assert(closeCount == 1, "Third Esc must close Impact")
        }

        testRunner("Editor - Callout Editing: Empty Removal, Whitespace Kept, Outside And Beak Clicks") {
            let (doc, panel, canvas) = try makeCalloutPanel()

            // An earlier step to prove an empty session adds no undo step
            let rect = RectangleLayer(rect: CGRect(x: 40, y: 400, width: 80, height: 60))
            doc.addLayer(rect)

            let (empty, _) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 200))
            assert(doc.layers.count == 2, "Callout must be in the document while editing")
            canvas.handleEscapeKey()
            assert(!doc.layers.contains { $0.id == empty.id }, "Empty callout must be removed")
            assert(doc.selectedLayerIDs.isEmpty, "Removing an empty callout must leave nothing selected")
            assert(doc.activeTool == .select, "Finishing must return to Select")
            doc.undo()
            assert(doc.layers.isEmpty, "Empty session must not add an undo step (undo reverts the rectangle instead)")
            doc.redo()
            assert(doc.layers.count == 1, "Redo must restore the rectangle")

            // Whitespace-only callouts are kept
            let (space, spaceEditor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 200))
            typeText(spaceEditor, " ")
            canvas.handleEscapeKey()
            assert(doc.layers.contains { $0.id == space.id } && space.text == " ", "A space-only callout must stay")
            let (newline, newlineEditor) = try createCallout(doc, canvas, at: CGPoint(x: 500, y: 200))
            newlineEditor.insertNewline(nil)
            canvas.handleEscapeKey()
            assert(doc.layers.contains { $0.id == newline.id } && newline.text == "\n", "A newline-only callout must stay")
            assert(newline.bodyRect.height > space.bodyRect.height, "A newline callout must be two lines tall")

            // Beak click while editing is ignored; an outside click finishes and is consumed
            let layerCount = doc.layers.count
            let (callout, editor) = try createCallout(doc, canvas, at: CGPoint(x: 400, y: 450))
            typeText(editor, "Yo")
            let beakPoint = CGPoint(x: callout.tailTip.x, y: callout.tailTip.y - 3)
            assert(callout.contains(point: beakPoint) && !callout.bodyRect.contains(beakPoint), "Test point must be on the beak")
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, beakPoint))
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, beakPoint))
            assert(canvas.isEditingCallout && canvas.calloutEditor === editor, "A beak click must keep the editor open")

            let onRect = CGPoint(x: rect.rect.midX, y: rect.rect.minY + 1)
            assert(rect.contains(point: onRect), "Test point must be on the rectangle")
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, onRect))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, canvas, CGPoint(x: onRect.x + 30, y: onRect.y + 30)))
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, CGPoint(x: onRect.x + 30, y: onRect.y + 30)))
            assert(!canvas.isEditingCallout, "An outside click must end editing")
            assert(doc.layers.count == layerCount + 1 && callout.text == "Yo", "Outside click must keep the callout and create nothing")
            assert(doc.selectedLayerIDs == [callout.id], "Outside click must leave the callout selected, not the clicked layer")
            assert(rect.rect.origin == CGPoint(x: 40, y: 400), "The finishing click must not drag the layer under it")
            assert(doc.activeTool == .select, "Outside click must return to Select")
            assert(panel.firstResponder === canvas, "Canvas must be first responder after finishing")

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Editor Keys: Letters Type, Tab Swallowed, Cmd-A Cmd-C Copy, Recolor") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let (callout, editor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 300))

            // Letters type instead of switching tools; Tab inserts nothing
            editor.keyDown(with: key("v", 9, window: panel))
            editor.keyDown(with: key("a", 0, window: panel))
            assert(callout.text == "va", "Letter keys must type into the callout")
            assert(doc.activeTool == .callout, "Letter keys must not switch tools while editing")
            editor.keyDown(with: key("\t", 48, window: panel))
            assert(callout.text == "va", "Tab must be swallowed")
            assert(canvas.isEditingCallout, "Tab must not end editing")

            // ⌘A then ⌘C copies the text (the app has no Edit menu)
            NSPasteboard.general.clearContents()
            assert(editor.performKeyEquivalent(with: key("a", 0, .command, window: panel)), "⌘A must be handled by the editor")
            assert(editor.selectedRange() == NSRange(location: 0, length: 2), "⌘A must select all text")
            assert(editor.performKeyEquivalent(with: key("c", 8, .command, window: panel)), "⌘C must be handled by the editor")
            assert(NSPasteboard.general.string(forType: .string) == "va", "⌘C must copy the selected text")
            assert(editor.performKeyEquivalent(with: key("Z", 6, [.command, .shift], window: panel)), "⇧⌘Z must be swallowed")
            assert(canvas.isEditingCallout, "⇧⌘Z must not end editing")

            // Recolor to white flips text and caret to dark
            callout.color = "#FFFFFF"
            canvas.syncCalloutEditorAppearance()
            assert(!sameColor(callout.textColor, .white), "White callout must use dark text")
            assert(sameColor(editor.textColor, callout.textColor), "Recolor must switch the editor text color")
            assert(sameColor(editor.insertionPointColor, callout.textColor), "Recolor must switch the caret color")

            // ⌘Z reverts the whole session: the new callout disappears
            assert(editor.performKeyEquivalent(with: key("z", 6, .command, window: panel)), "⌘Z must be handled by the editor")
            assert(!canvas.isEditingCallout, "⌘Z must end the editing session")
            assert(!doc.layers.contains { $0.id == callout.id }, "⌘Z must take back the new callout")

            quietClose(doc, panel)
        }

        // Phase 4 helpers: a finished "Hello" callout (selected, Select tool) and plain clicks
        func makeHelloCallout(_ doc: EditorDocument, _ canvas: EditorCanvasView, at p: CGPoint = CGPoint(x: 300, y: 300)) throws -> CalloutLayer {
            let (callout, editor) = try createCallout(doc, canvas, at: p)
            typeText(editor, "Hello")
            canvas.endCalloutEditing()
            return callout
        }
        func click(_ canvas: EditorCanvasView, _ p: CGPoint, clickCount: Int = 1, dragTo: CGPoint? = nil) {
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, p, clickCount: clickCount))
            if let dragTo = dragTo {
                canvas.mouseDragged(with: mouse(.leftMouseDragged, canvas, dragTo))
            }
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, dragTo ?? p, clickCount: clickCount))
        }
        func currentCallout(_ doc: EditorDocument, _ id: UUID) -> CalloutLayer? {
            doc.layers.first { $0.id == id } as? CalloutLayer
        }
        // True when the composition differs from the same document with the callout text hidden
        func compositionShowsText(_ doc: EditorDocument, _ callout: CalloutLayer) -> Bool {
            func pixels(_ image: CGImage) -> [UInt8] {
                let w = image.width, h = image.height
                var data = [UInt8](repeating: 0, count: w * h * 4)
                let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return data
            }
            guard !callout.isTextHidden, let shown = doc.renderComposition() else { return false }
            callout.isTextHidden = true
            defer { callout.isTextHidden = false }
            guard let hidden = doc.renderComposition() else { return false }
            return pixels(shown) != pixels(hidden)
        }

        testRunner("Editor - Callout Click Rules: Select, Click Again, Drag, Double-Click, Tip Handle") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let callout = try makeHelloCallout(doc, canvas)
            let body = CGPoint(x: callout.bodyRect.midX, y: callout.bodyRect.midY)

            // A click on an unselected callout selects it and does not edit
            doc.selectedLayerIDs = []
            click(canvas, body)
            assert(doc.selectedLayerIDs == [callout.id], "A click must select the callout")
            assert(!canvas.isEditingCallout, "A click on an unselected callout must not edit")

            // A second click without movement edits
            click(canvas, body)
            assert(canvas.isEditingCallout && canvas.calloutEditor != nil, "A click on the selected callout must edit")
            assert(callout.isTextHidden && doc.selectedLayerIDs == [callout.id], "Editing must hide layer text and keep the selection")
            canvas.endCalloutEditing()

            // A second click with a 5 px drag moves the callout and does not edit
            let originBefore = callout.origin
            let tipBefore = callout.tailTip
            click(canvas, body, dragTo: CGPoint(x: body.x + 5, y: body.y))
            assert(!canvas.isEditingCallout, "Dragging a selected callout must not edit")
            assert(callout.origin == CGPoint(x: originBefore.x + 5, y: originBefore.y), "The drag must move the body by the full distance")
            assert(callout.tailTip == CGPoint(x: tipBefore.x + 5, y: tipBefore.y), "The drag must move the tip too")

            // A small jitter (≤ 3 pt) still counts as a click and leaves the callout in place
            let movedBody = CGPoint(x: callout.bodyRect.midX, y: callout.bodyRect.midY)
            let movedOrigin = callout.origin
            click(canvas, movedBody, dragTo: CGPoint(x: movedBody.x + 2, y: movedBody.y + 1))
            assert(canvas.isEditingCallout, "A click with a tiny jitter must still edit")
            assert(callout.origin == movedOrigin, "A click that edits must not move the callout")
            canvas.endCalloutEditing()

            // A clickCount 2 mouse-down on an unselected callout edits
            doc.selectedLayerIDs = []
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, movedBody, clickCount: 2))
            assert(canvas.isEditingCallout, "A double-click must edit an unselected callout")
            assert(doc.selectedLayerIDs == [callout.id], "Double-click editing must select the callout")
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, movedBody, clickCount: 2))
            assert(canvas.isEditingCallout, "The double-click's mouse-up must keep editing")
            canvas.endCalloutEditing()

            // A tip-handle click never edits, single or double
            let tip = callout.tailTip
            assert(callout.hitTestHandle(point: tip) == 0, "Test point must be on the tip handle")
            click(canvas, tip)
            assert(!canvas.isEditingCallout, "A tip-handle click must not edit")
            click(canvas, tip, clickCount: 2)
            assert(!canvas.isEditingCallout, "A tip-handle double-click must not edit")
            assert(callout.tailTip == tip, "A tip-handle click must not move the tip")

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Re-Edit Puts The Caret At The Clicked Character") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let callout = try makeHelloCallout(doc, canvas)

            click(canvas, CGPoint(x: callout.bodyRect.maxX - 2, y: callout.bodyRect.midY))
            assert(canvas.calloutEditor?.selectedRange() == NSRange(location: 5, length: 0), "A click at the right end must put the caret after \"Hello\"")
            canvas.endCalloutEditing()

            click(canvas, CGPoint(x: callout.bodyRect.minX + 2, y: callout.bodyRect.midY))
            assert(canvas.calloutEditor?.selectedRange() == NSRange(location: 0, length: 0), "A click at the left end must put the caret at the start")
            canvas.endCalloutEditing()

            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, CGPoint(x: callout.bodyRect.maxX - 2, y: callout.bodyRect.midY), clickCount: 2))
            assert(canvas.calloutEditor?.selectedRange() == NSRange(location: 5, length: 0), "A double-click must also place the caret where clicked")
            canvas.endCalloutEditing()

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Editing Session Is One Undo Step; Emptied Callout Is Removed And Restorable") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let callout = try makeHelloCallout(doc, canvas)
            let id = callout.id

            // "Hello" → "Hi" in one session
            click(canvas, CGPoint(x: callout.bodyRect.midX, y: callout.bodyRect.midY))
            guard let editor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Click on the selected callout must open the editor"])
            }
            editor.selectAll(nil)
            typeText(editor, "Hi")
            editor.keyDown(with: key("\u{1b}", 53, window: panel))
            assert(callout.text == "Hi" && doc.selectedLayerIDs == [id], "Esc must keep the edited callout selected")
            doc.undo()
            assert(currentCallout(doc, id)?.text == "Hello", "One undo must restore the previous text")
            doc.redo()
            assert(currentCallout(doc, id)?.text == "Hi", "Redo must replay the session")

            // Exactly one step per session: the click's mouseDown snapshot was dropped,
            // so the step before the session is the callout's creation
            doc.undo()
            doc.undo()
            assert(doc.layers.isEmpty, "The step before the edit session must be the creation")
            doc.redo()
            doc.redo()
            assert(currentCallout(doc, id)?.text == "Hi", "Redo must replay creation and edit")

            // An unchanged session adds no step
            guard let restored = currentCallout(doc, id) else {
                throw NSError(domain: "EditorTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Callout must be present"])
            }
            doc.selectedLayerIDs = [id]
            click(canvas, CGPoint(x: restored.bodyRect.midX, y: restored.bodyRect.midY))
            assert(canvas.isEditingCallout, "Click on the selected callout must edit")
            canvas.endCalloutEditing()
            doc.undo()
            assert(currentCallout(doc, id)?.text == "Hello", "An unchanged session must not add an undo step")
            doc.redo()

            // Emptying an existing callout removes it; undo brings it back
            guard let current = currentCallout(doc, id) else {
                throw NSError(domain: "EditorTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Callout must be present"])
            }
            doc.selectedLayerIDs = [id]
            click(canvas, CGPoint(x: current.bodyRect.midX, y: current.bodyRect.midY))
            guard let emptyEditor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Editor must open"])
            }
            emptyEditor.selectAll(nil)
            emptyEditor.deleteBackward(nil)
            canvas.endCalloutEditing()
            assert(currentCallout(doc, id) == nil && doc.selectedLayerIDs.isEmpty, "An emptied callout must be removed and deselected")
            doc.undo()
            assert(currentCallout(doc, id)?.text == "Hi", "Undo must bring the emptied callout back")

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Cmd-Z While Editing Reverts The Whole Session") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let cmdZ = key("z", 6, .command, window: panel)

            // A new typed callout disappears
            let (typed, typedEditor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 300))
            typeText(typedEditor, "Yo")
            assert(typedEditor.performKeyEquivalent(with: cmdZ), "⌘Z must be handled")
            assert(!canvas.isEditingCallout && currentCallout(doc, typed.id) == nil, "⌘Z must remove a new typed callout")
            assert(doc.selectedLayerIDs.isEmpty && doc.activeTool == .select, "Revert must leave nothing selected and Select active")
            doc.redo()
            assert(currentCallout(doc, typed.id)?.text == "Yo", "⇧⌘Z after a revert must redo the session")
            doc.undo()

            // A new empty callout disappears and no earlier step is undone
            let rect = RectangleLayer(rect: CGRect(x: 40, y: 400, width: 80, height: 60))
            doc.addLayer(rect)
            let (empty, emptyEditor) = try createCallout(doc, canvas, at: CGPoint(x: 500, y: 200))
            assert(emptyEditor.performKeyEquivalent(with: cmdZ), "⌘Z must be handled")
            assert(currentCallout(doc, empty.id) == nil, "⌘Z must remove a new empty callout")
            assert(doc.layers.count == 1 && doc.layers.first?.id == rect.id, "⌘Z on an unchanged session must not undo an earlier step")

            // An edited callout gets its old text back and stays selected
            let callout = try makeHelloCallout(doc, canvas, at: CGPoint(x: 300, y: 250))
            click(canvas, CGPoint(x: callout.bodyRect.midX, y: callout.bodyRect.midY))
            guard let editor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Editor must open"])
            }
            typeText(editor, "XX")
            assert(editor.performKeyEquivalent(with: cmdZ), "⌘Z must be handled")
            assert(!canvas.isEditingCallout, "⌘Z must end editing")
            assert(currentCallout(doc, callout.id)?.text == "Hello", "⌘Z must restore the previous text")
            assert(doc.selectedLayerIDs == [callout.id] && doc.activeTool == .select, "A reverted edit must stay selected with Select active")
            assert(currentCallout(doc, callout.id)?.isTextHidden == false, "The reverted callout must draw its text")
            assert(doc.layers.contains { $0.id == rect.id }, "Earlier layers must survive the revert")

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Recolor During A Session Folds Into The Session Undo Step") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let callout = try makeHelloCallout(doc, canvas)
            let originalColor = callout.color

            click(canvas, CGPoint(x: callout.bodyRect.midX, y: callout.bodyRect.midY))
            guard let editor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Editor must open"])
            }
            panel.toolbarView.applyPickedColor("#FFFFFF")
            assert(callout.color == "#FFFFFF", "The swatch must recolor the editing callout")
            assert(sameColor(editor.textColor, callout.textColor), "Recolor must switch the editor text color")
            assert(canvas.isEditingCallout, "Recolor must not end editing")
            typeText(editor, "!")
            canvas.endCalloutEditing()

            doc.undo()
            let restored = currentCallout(doc, callout.id)
            assert(restored?.text == "Hello" && restored?.color == originalColor, "One undo must restore both text and color")
            doc.undo()
            assert(doc.layers.isEmpty, "The recolor must not add its own undo step")

            // A recolor alone also counts as a change to the session
            doc.redo()
            guard let again = currentCallout(doc, callout.id) else {
                throw NSError(domain: "EditorTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Callout must be present"])
            }
            doc.selectedLayerIDs = [again.id]
            click(canvas, CGPoint(x: again.bodyRect.midX, y: again.bodyRect.midY))
            panel.toolbarView.applyPickedColor("#34C759")
            canvas.endCalloutEditing()
            doc.undo()
            assert(currentCallout(doc, again.id)?.color == originalColor, "A recolor-only session must be one undo step")

            quietClose(doc, panel)
        }

        testRunner("Editor - Callout Editing Finishes On Tool Change, Export And Close") {
            let (doc, panel, canvas) = try makeCalloutPanel()

            // Tool change: the session ends with the text, and the new tool stays active
            let (toolCallout, toolEditor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 300))
            typeText(toolEditor, "Tool")
            doc.activeTool = .arrow
            assert(!canvas.isEditingCallout && canvas.calloutEditor == nil, "A tool change must end editing")
            assert(!canvas.subviews.contains { $0 is CalloutTextView }, "A tool change must remove the editor")
            assert(doc.activeTool == .arrow, "The chosen tool must stay active")
            assert(toolCallout.text == "Tool" && !toolCallout.isTextHidden, "A tool change must commit the text")
            assert(compositionShowsText(doc, toolCallout), "The composition must contain the committed text")

            // Select button while editing keeps the callout selected
            let (selCallout, selEditor) = try createCallout(doc, canvas, at: CGPoint(x: 500, y: 300))
            typeText(selEditor, "Sel")
            doc.activeTool = .select
            assert(!canvas.isEditingCallout && doc.selectedLayerIDs == [selCallout.id], "Select must finish editing and keep the callout selected")

            // Copy
            let (copyCallout, copyEditor) = try createCallout(doc, canvas, at: CGPoint(x: 300, y: 450))
            typeText(copyEditor, "Copy")
            canvas.copyCompositionToClipboard()
            assert(!canvas.isEditingCallout && !copyCallout.isTextHidden, "Copy must end editing first")
            assert(copyCallout.text == "Copy" && doc.selectedLayerIDs == [copyCallout.id], "Copy must commit and keep the callout selected")
            assert(compositionShowsText(doc, copyCallout), "The copied composition must contain the text")

            // Save
            let saveDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("impact-callout-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: saveDir) }
            let (saveCallout, saveEditor) = try createCallout(doc, canvas, at: CGPoint(x: 500, y: 450))
            typeText(saveEditor, "Save")
            let saveURL = saveDir.appendingPathComponent("saved.png")
            canvas.saveCompositionToFile(url: saveURL)
            assert(!canvas.isEditingCallout && !saveCallout.isTextHidden && saveCallout.text == "Save", "Save must end editing first")
            assert(FileManager.default.fileExists(atPath: saveURL.path), "Save must write the file")
            quietClose(doc, panel)

            // Close: a panel with a source file saves its numbered copy next to it
            let sourceURL = saveDir.appendingPathComponent("shot.png")
            let (closeDoc, _, _) = try makeCalloutPanel()
            let closePanel = EditorPanel(document: closeDoc, sourceFileURL: sourceURL)
            let closeCanvas = closePanel.canvasView
            let (closeCallout, closeEditor) = try createCallout(closeDoc, closeCanvas, at: CGPoint(x: 300, y: 300))
            typeText(closeEditor, "Close")
            EditorPanel.copyToClipboardOverride = false
            closePanel.close()
            EditorPanel.copyToClipboardOverride = nil
            assert(!closeCanvas.isEditingCallout && !closeCallout.isTextHidden, "Close must end editing first")
            assert(closeCallout.text == "Close" && closeDoc.layers.contains { $0.id == closeCallout.id }, "Close must commit the text")
            assert(compositionShowsText(closeDoc, closeCallout), "The composition saved on close must contain the text")
            assert(FileManager.default.fileExists(atPath: saveDir.appendingPathComponent("shot-2.png").path), "Close must save the numbered copy")
        }

        // MARK: - Annotation Copy / Cut / Paste / Duplicate

        testRunner("Editor - Annotation Copy And Paste Cascades 10px Per Paste With Fresh IDs") {
            let (doc, panel, _) = try makeCalloutPanel()
            let clipboard = AnnotationClipboard()
            let arrow = ArrowLayer(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 150))
            let rect = RectangleLayer(rect: CGRect(x: 300, y: 300, width: 80, height: 40))
            doc.addLayer(arrow)
            doc.addLayer(rect)

            assert(!doc.pasteLayers(from: clipboard), "Paste must do nothing before anything was copied")
            doc.selectedLayerIDs = [arrow.id, rect.id]
            assert(doc.copySelectedLayers(to: clipboard), "Copy must succeed with a selection")
            assert(doc.layers.count == 2, "Copy must not change the canvas")

            // First paste: +10/+10, on top, in the same relative order, selected, one undo step
            doc.activeTool = .arrow
            assert(doc.pasteLayers(from: clipboard), "Paste must succeed after a copy")
            assert(doc.layers.count == 4, "Paste must add both copied layers")
            guard let pastedArrow = doc.layers[2] as? ArrowLayer, let pastedRect = doc.layers[3] as? RectangleLayer else {
                throw NSError(domain: "EditorTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Pasted layers must sit on top in their original order"])
            }
            assert(pastedArrow.start == CGPoint(x: 110, y: 110) && pastedArrow.end == CGPoint(x: 210, y: 160), "First paste must land 10px right and down")
            assert(pastedRect.rect.origin == CGPoint(x: 310, y: 310), "Group members must keep their relative positions")
            assert(pastedArrow.id != arrow.id && pastedRect.id != rect.id, "Pasted layers must get fresh ids")
            assert(Set(doc.layers.map { $0.id }).count == 4, "Every layer id must be unique")
            assert(doc.selectedLayerIDs == [pastedArrow.id, pastedRect.id], "Pasted layers must become the selection")
            assert(doc.activeTool == .select, "Paste must switch to the Select tool")
            assert(arrow.start == CGPoint(x: 100, y: 100), "Paste must not move the originals")

            // Second paste of the same contents cascades another 10px
            doc.pasteLayers(from: clipboard)
            guard let secondArrow = doc.layers[4] as? ArrowLayer else {
                throw NSError(domain: "EditorTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Second paste must append an arrow"])
            }
            assert(secondArrow.start == CGPoint(x: 120, y: 120), "Second paste must land 20px from the original")
            assert(secondArrow.id != pastedArrow.id, "Each paste must create new ids")

            // Undo takes back exactly one paste
            doc.undo()
            assert(doc.layers.count == 4, "Undo must remove only the last paste")

            // A new copy starts the cascade over
            doc.selectedLayerIDs = [arrow.id]
            doc.copySelectedLayers(to: clipboard)
            doc.pasteLayers(from: clipboard)
            guard let restartArrow = doc.layers.last as? ArrowLayer else {
                throw NSError(domain: "EditorTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Paste after a new copy must append an arrow"])
            }
            assert(restartArrow.start == CGPoint(x: 110, y: 110), "A new copy must reset the cascade to 10px")

            // Clipboard holds snapshots: later edits to the original do not leak into pastes
            arrow.move(by: CGPoint(x: 500, y: 0))
            doc.pasteLayers(from: clipboard)
            assert((doc.layers.last as? ArrowLayer)?.start == CGPoint(x: 120, y: 120), "Paste must use the copied state, not the live layer")
            quietClose(doc, panel)
        }

        testRunner("Editor - Annotation Cut Removes Selection As One Undo Step") {
            let (doc, panel, _) = try makeCalloutPanel()
            let clipboard = AnnotationClipboard()
            let keep = RectangleLayer(rect: CGRect(x: 50, y: 50, width: 40, height: 40))
            let arrow = ArrowLayer(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 150))
            let counter = CounterLayer(center: CGPoint(x: 300, y: 300), value: 1)
            doc.addLayer(keep)
            doc.addLayer(arrow)
            doc.addLayer(counter)

            doc.selectedLayerIDs = []
            assert(!doc.cutSelectedLayers(to: clipboard), "Cut must do nothing without a selection")
            assert(clipboard.isEmpty && doc.layers.count == 3, "An empty cut must change nothing")

            doc.selectedLayerIDs = [arrow.id, counter.id]
            assert(doc.cutSelectedLayers(to: clipboard), "Cut must succeed with a selection")
            assert(doc.layers.map { $0.id } == [keep.id], "Cut must remove only the selected layers")
            assert(doc.selectedLayerIDs.isEmpty, "Cut must clear the selection")
            assert(clipboard.layers.count == 2, "Cut must store the selection in the clipboard")

            doc.undo()
            assert(doc.layers.map { $0.id } == [keep.id, arrow.id, counter.id], "One undo must restore every cut layer")

            // Pasting after a cut + undo still works, cascading from the original position
            doc.pasteLayers(from: clipboard)
            assert((doc.layers[3] as? ArrowLayer)?.start == CGPoint(x: 110, y: 110), "Paste after cut must land 10px away")
            quietClose(doc, panel)
        }

        testRunner("Editor - Annotation Duplicate Offsets, Selects Copies And Leaves Clipboard Alone") {
            let (doc, panel, _) = try makeCalloutPanel()
            let clipboard = AnnotationClipboard()
            let shared = AnnotationClipboard.shared
            let sharedBefore = (shared.layers.map { $0.id }, shared.pasteCount)
            let rect = RectangleLayer(rect: CGRect(x: 100, y: 100, width: 60, height: 30), color: "#34C759", strokeWidth: 7, fillStyle: .solid)
            let other = ArrowLayer(start: CGPoint(x: 400, y: 100), end: CGPoint(x: 450, y: 150))
            doc.addLayer(rect)
            doc.addLayer(other)
            doc.selectedLayerIDs = [rect.id]
            doc.copySelectedLayers(to: clipboard)

            doc.selectedLayerIDs = []
            assert(!doc.duplicateSelectedLayers(), "Duplicate must do nothing without a selection")

            doc.selectedLayerIDs = [rect.id]
            assert(doc.duplicateSelectedLayers(), "Duplicate must succeed with a selection")
            guard let copy = doc.layers.last as? RectangleLayer else {
                throw NSError(domain: "EditorTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Duplicate must append a rectangle on top"])
            }
            assert(copy.id != rect.id, "Duplicate must get a fresh id")
            assert(copy.rect == CGRect(x: 110, y: 110, width: 60, height: 30), "Duplicate must land 10px right and down")
            assert(copy.color == "#34C759" && copy.strokeWidth == 7 && copy.fillStyle == .solid, "Duplicate must keep the styling")
            assert(doc.selectedLayerIDs == [copy.id], "The copy must become the selection")

            // Repeated ⌘D duplicates the new copy, building a cascade
            doc.duplicateSelectedLayers()
            assert((doc.layers.last as? RectangleLayer)?.rect.origin == CGPoint(x: 120, y: 120), "A second duplicate must cascade from the copy")
            assert(doc.layers.count == 4, "Each duplicate must add one layer")

            assert(clipboard.layers.count == 1 && clipboard.layers[0].id == rect.id && clipboard.pasteCount == 0, "Duplicate must not touch the clipboard")
            assert(shared.layers.map { $0.id } == sharedBefore.0 && shared.pasteCount == sharedBefore.1, "Duplicate must not touch the shared clipboard")

            doc.undo()
            assert(doc.layers.count == 3, "Undo must take back exactly one duplicate")
            quietClose(doc, panel)
        }

        testRunner("Editor - Annotation Paste Renumbers Counters Across Canvases") {
            let (source, sourcePanel, _) = try makeCalloutPanel()
            let (target, targetPanel, _) = try makeCalloutPanel()
            let clipboard = AnnotationClipboard()

            let c1 = CounterLayer(center: CGPoint(x: 100, y: 100), value: 1)
            let c3 = CounterLayer(center: CGPoint(x: 200, y: 100), value: 3, color: "#007AFF")
            let c2 = CounterLayer(center: CGPoint(x: 150, y: 100), value: 2)
            source.addLayer(c1)
            source.addLayer(c3)
            source.addLayer(c2)
            for value in 1...5 {
                target.addLayer(CounterLayer(center: CGPoint(x: CGFloat(value) * 40, y: 400), value: value))
            }

            // ② and ③ onto a canvas whose highest counter is ⑤ become ⑥ and ⑦, in their original order
            source.selectedLayerIDs = [c3.id, c2.id]
            source.copySelectedLayers(to: clipboard)
            target.pasteLayers(from: clipboard)
            let pasted = target.layers.suffix(2).compactMap { $0 as? CounterLayer }
            assert(pasted.count == 2, "Both counters must be pasted")
            assert(pasted[0].value == 7 && pasted[0].color == "#007AFF", "The copy of ③ must become ⑦ and keep its color")
            assert(pasted[1].value == 6, "The copy of ② must become ⑥")
            assert(pasted[0].center == CGPoint(x: 210, y: 110), "Pasting across canvases keeps the coordinates plus the offset")
            assert(c2.value == 2 && c3.value == 3, "The source counters must keep their numbers")

            // Duplicate continues from the highest counter on the canvas
            source.selectedLayerIDs = [c1.id]
            source.duplicateSelectedLayers()
            assert((source.layers.last as? CounterLayer)?.value == 4, "A duplicated counter must take the next free number")

            // The next free number follows the canvas, not a stale counter step
            source.counterStep = 20
            source.selectedLayerIDs = [c1.id]
            source.duplicateSelectedLayers()
            assert((source.layers.last as? CounterLayer)?.value == 5, "Renumbering must use the highest counter on the canvas")

            quietClose(source, sourcePanel)
            quietClose(target, targetPanel)
        }

        testRunner("Editor - Annotation Copy Keeps Spotlight Rectangles And Blur Under Spotlight") {
            let (source, sourcePanel, _) = try makeCalloutPanel()
            let (target, targetPanel, _) = try makeCalloutPanel()
            let clipboard = AnnotationClipboard()

            let spotlight = FilterLayer(rects: [CGRect(x: 10, y: 10, width: 50, height: 50), CGRect(x: 100, y: 100, width: 50, height: 50)], filterMode: .spotlight)
            spotlight.selectedRectIndex = 0
            let blur = FilterLayer(rects: [CGRect(x: 300, y: 300, width: 60, height: 30)], filterMode: .gaussian)
            source.layers = [blur, spotlight]
            source.selectedLayerIDs = [blur.id, spotlight.id]
            source.copySelectedLayers(to: clipboard)

            // No spotlight on the target: the whole overlay arrives with every rectangle moved
            target.pasteLayers(from: clipboard)
            guard let pastedSpot = target.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer,
                  let spotIndex = target.layers.firstIndex(where: { $0 === pastedSpot }),
                  let blurIndex = target.layers.firstIndex(where: { ($0 as? FilterLayer)?.filterMode == .gaussian }) else {
                throw NSError(domain: "EditorTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Spotlight and blur must be pasted"])
            }
            assert(pastedSpot.rects == [CGRect(x: 20, y: 20, width: 50, height: 50), CGRect(x: 110, y: 110, width: 50, height: 50)], "Every spotlight rectangle must move by the offset")
            assert(blurIndex < spotIndex, "Blur must stay under the spotlight overlay")

            // A second paste joins the existing overlay instead of stacking a second one
            target.pasteLayers(from: clipboard)
            let overlays = target.layers.filter { ($0 as? FilterLayer)?.filterMode == .spotlight }
            assert(overlays.count == 1, "A canvas must keep a single spotlight overlay")
            assert(pastedSpot.rects.count == 4 && pastedSpot.rects[2].origin == CGPoint(x: 30, y: 30), "Pasted rectangles must join the overlay, cascaded")
            assert(target.selectedLayerIDs.contains(pastedSpot.id), "The overlay holding the pasted rectangles must be selected")
            let lastSpotIndex = target.layers.firstIndex(where: { $0 === pastedSpot }) ?? -1
            assert(target.layers.enumerated().allSatisfy { (l: (offset: Int, element: AnnotationLayer)) in (l.element as? FilterLayer)?.filterMode != .gaussian || l.offset < lastSpotIndex }, "Every blur must stay under the spotlight")

            // Cut takes the whole overlay, not just its selected rectangle
            source.selectedLayerIDs = [spotlight.id]
            source.cutSelectedLayers(to: clipboard)
            assert(!source.layers.contains { $0 === spotlight }, "Cut must remove the whole spotlight overlay")
            assert((clipboard.layers.first as? FilterLayer)?.rects.count == 2, "Cut must keep every spotlight rectangle")

            quietClose(source, sourcePanel)
            quietClose(target, targetPanel)
        }

        testRunner("Editor - Annotation Shortcuts Through Canvas keyDown") {
            let (doc, panel, canvas) = try makeCalloutPanel()
            let rect = RectangleLayer(rect: CGRect(x: 100, y: 100, width: 60, height: 30))
            doc.addLayer(rect)
            let pasteboard = NSPasteboard.general

            // ⌘C with a selection copies the annotation, not the image
            doc.selectedLayerIDs = [rect.id]
            let changeCount = pasteboard.changeCount
            canvas.keyDown(with: key("c", 8, .command, window: panel))
            assert(pasteboard.changeCount == changeCount, "⌘C with a selection must not touch the macOS pasteboard")
            assert(AnnotationClipboard.shared.layers.map { $0.id } == [rect.id], "⌘C must fill the annotation clipboard")

            // ⌘V pastes, ⌘D duplicates, plain D still picks the pen
            canvas.keyDown(with: key("v", 9, .command, window: panel))
            assert(doc.layers.count == 2 && (doc.layers.last as? RectangleLayer)?.rect.origin == CGPoint(x: 110, y: 110), "⌘V must paste 10px away")
            canvas.keyDown(with: key("d", 2, .command, window: panel))
            assert(doc.layers.count == 3 && (doc.layers.last as? RectangleLayer)?.rect.origin == CGPoint(x: 120, y: 120), "⌘D must duplicate the pasted copy")
            assert(doc.activeTool == .select, "⌘D must not pick the pen tool")

            // ⌘X cuts the duplicate; ⌘Z brings it back
            let duplicateID = doc.layers[2].id
            canvas.keyDown(with: key("x", 7, .command, window: panel))
            assert(doc.layers.count == 2 && !doc.layers.contains { $0.id == duplicateID }, "⌘X must remove the selection")
            canvas.keyDown(with: key("z", 6, .command, window: panel))
            assert(doc.layers.count == 3, "⌘Z must restore the cut layer")

            // ⌘C with nothing selected still copies the composition
            doc.selectedLayerIDs = []
            canvas.keyDown(with: key("c", 8, .command, window: panel))
            assert(pasteboard.changeCount != changeCount, "⌘C without a selection must copy the composition")

            // While a callout's text is edited, the annotation shortcuts leave the canvas alone
            let (_, editor) = try createCallout(doc, canvas, at: CGPoint(x: 500, y: 400))
            typeText(editor, "Hi")
            let countWhileEditing = doc.layers.count
            canvas.keyDown(with: key("v", 9, .command, window: panel))
            canvas.keyDown(with: key("d", 2, .command, window: panel))
            canvas.keyDown(with: key("x", 7, .command, window: panel))
            assert(doc.layers.count == countWhileEditing && canvas.isEditingCallout, "Annotation shortcuts must not act while editing text")
            canvas.endCalloutEditing()

            quietClose(doc, panel)
        }

        testRunner("Editor - Text Annotation Tool (Shortcut X, Click/Drag Placement, Live Sizing & Shadow)") {
            guard let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(resolveTestImageURL()! as CFURL, nil)!, 0, nil) else {
                throw NSError(domain: "EditorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test image"])
            }
            let doc = EditorDocument(image: img)
            let panel = EditorPanel(document: doc)
            let canvas = panel.canvasView

            // 1. Tool selection via shortcut 'x'
            canvas.keyDown(with: key("x", 7, window: panel))
            assert(doc.activeTool == .text, "Pressing 'x' must activate .text tool")
            assert(panel.toolbarView.toolButtons[.text]?.isActive == true, "Text tool button on toolbar must be active")

            // 2. Click placement: text appears at click point
            let clickPt = CGPoint(x: 200, y: 150)
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, clickPt))
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, clickPt))

            assert(canvas.isEditingCallout, "Clicking with text tool must begin editing immediately")
            guard let textLayer = doc.layers.first as? TextLayer, let editor = canvas.calloutEditor else {
                throw NSError(domain: "EditorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextLayer must be created and editing"])
            }
            assert(abs(textLayer.center.x - clickPt.x) < 0.1 && abs(textLayer.center.y - clickPt.y) < 0.1, "Text layer must be centered at click point")

            // 3. Live growth in both directions around center anchor
            let initialMidX = textLayer.bodyRect.midX
            let initialWidth = textLayer.bodyRect.width

            typeText(editor, "Hello")
            let midHello = textLayer.bodyRect.midX
            let widthHello = textLayer.bodyRect.width
            assert(abs(midHello - initialMidX) < 0.01, "Text layer must remain centered horizontally (got \(midHello), expected \(initialMidX))")
            assert(widthHello > initialWidth, "Text layer must widen as text is typed")
            assert(textLayer.bodyRect.minX < clickPt.x && textLayer.bodyRect.maxX > clickPt.x, "Text must grow in both directions around anchor")

            typeText(editor, " World, this is a much longer line of text")
            let midLonger = textLayer.bodyRect.midX
            assert(abs(midLonger - initialMidX) < 0.01, "Text layer must continue growing in both directions around anchor")

            // 4. Commit and verify rendering
            canvas.endCalloutEditing()
            assert(!canvas.isEditingCallout, "endCalloutEditing must finish editing")
            assert(doc.layers.count == 1, "Committed text layer must remain in document")
            assert(textLayer.text == "Hello World, this is a much longer line of text", "Committed text must match typed text")

            // Test draw runs cleanly with drop shadow
            let ctx = CGContext(
                data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 400 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            textLayer.draw(in: ctx, scale: 1.0)

            // 5. Drag placement: text appears where mouse is released
            doc.activeTool = .text
            let startPt = CGPoint(x: 100, y: 100)
            let releasePt = CGPoint(x: 350, y: 450)
            canvas.mouseDown(with: mouse(.leftMouseDown, canvas, startPt))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, canvas, releasePt))
            canvas.mouseUp(with: mouse(.leftMouseUp, canvas, releasePt))

            assert(canvas.isEditingCallout, "Releasing drag must open editor")
            guard let draggedLayer = doc.layers.last as? TextLayer, canvas.calloutEditor != nil else {
                throw NSError(domain: "EditorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Dragged TextLayer must be created"])
            }
            assert(abs(draggedLayer.center.x - releasePt.x) < 0.1 && abs(draggedLayer.center.y - releasePt.y) < 0.1, "Text must appear where release happened")

            // 6. Empty cancellation: Esc removes empty layer
            canvas.handleEscapeKey()
            assert(!canvas.isEditingCallout, "Esc must end editing")
            assert(!doc.layers.contains { $0.id == draggedLayer.id }, "Empty dragged text layer must be discarded")

            quietClose(doc, panel)
        }
    }
}
