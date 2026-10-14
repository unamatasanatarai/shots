import Foundation
import CoreGraphics
import AppKit

// MARK: - Layer Types

public enum LayerType: String, Codable, CaseIterable {
    case select = "Select"
    case crop = "Crop"
    case arrow = "Arrow"
    case callout = "Speech Bubble"
    case text = "Plain Text"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case pen = "Pen"
    case line = "Line"
    case counter = "Counter Badge"
    case dimension = "Dimension Line"
    case magnifier = "Magnifier"
    case spotlight = "Spotlight"
    case blur = "Blur / Pixelate"
    case highlighter = "Highlighter"
    case bezel = "Bezel / Frame"
    case imageOverlay = "Image Overlay"
}

// MARK: - Arrow Head Types

public enum ArrowHeadType: String, Codable {
    case standard
    case filled
    case biDirectional
}

// MARK: - Filter Modes

public enum FilterMode: String, Codable {
    case gaussian
    case pixelate
    case spotlight
}

// MARK: - Core Annotation Layer Protocol

public protocol AnnotationLayer: AnyObject {
    var id: UUID { get }
    var type: LayerType { get }
    var zIndex: Int { get set }
    var isVisible: Bool { get set }
    var color: String { get set } // Hex representation e.g. "#FF3B30"
    var strokeWidth: CGFloat { get set }

    /// Crucial for Elastic Canvas: calculates outer bounds including strokes, curves, and anchors
    func getBoundingBox() -> CGRect

    /// Hit test against layer geometry for selection
    func contains(point: CGPoint) -> Bool

    /// Control handle hit testing (returns handle index if hit)
    func hitTestHandle(point: CGPoint, radius: CGFloat) -> Int?

    /// Translates layer by delta vector
    func move(by delta: CGPoint)

    /// Moves a specific control handle
    func updateHandle(index: Int, to point: CGPoint)

    /// Renders vector content into CGContext
    func draw(in context: CGContext, scale: CGFloat)

    /// Clones layer for undo/redo snapshots
    func clone() -> AnnotationLayer
}

public extension AnnotationLayer {
    func hitTestHandle(point: CGPoint) -> Int? {
        hitTestHandle(point: point, radius: 8.0)
    }
}

// MARK: - Color Hex Helpers

public extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)

        let r, g, b: CGFloat
        if cleanHex.count == 6 {
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
        } else {
            r = 1.0; g = 0.2; b = 0.2
        }

        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF0000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
