import Foundation
import CoreGraphics
import AppKit
import os

// MARK: - Layer Types

public enum LayerType: String, Codable, CaseIterable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case pen = "Pen"
    case line = "Line"
    case counter = "Counter"
    case dimension = "Ruler"
    case spotlight = "Spotlight"
    case blur = "Blur"
    case highlighter = "Highlighter"
    case callout = "Callout"
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

// MARK: - Color Hex & CGColor Performance Cache

public final class FastColor {
    public static let shared = FastColor()

    private var cgColorCache: [String: CGColor] = [:]
    private var nsColorCache: [String: NSColor] = [:]
    private let lock = NSLock()

    @inline(__always)
    private static func hexNibble(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 48...57: return UInt32(byte - 48)       // '0'...'9'
        case 65...70: return UInt32(byte - 65 + 10)  // 'A'...'F'
        case 97...102: return UInt32(byte - 97 + 10) // 'a'...'f'
        default: return nil
        }
    }

    public static func parseRGB(from hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let utf8 = hex.utf8
        var startIndex = utf8.startIndex
        if let first = utf8.first, first == 35 { // '#'
            startIndex = utf8.index(after: startIndex)
        }
        var val: UInt32 = 0
        var count = 0
        var curr = startIndex
        while curr < utf8.endIndex && count < 6 {
            guard let nibble = hexNibble(utf8[curr]) else { break }
            val = (val << 4) | nibble
            count += 1
            curr = utf8.index(after: curr)
        }
        if count == 6 {
            let r = CGFloat((val >> 16) & 0xFF) / 255.0
            let g = CGFloat((val >> 8) & 0xFF) / 255.0
            let b = CGFloat(val & 0xFF) / 255.0
            return (r, g, b)
        }
        return (1.0, 0.2, 0.2)
    }

    public func cgColor(hex: String, alpha: CGFloat = 1.0) -> CGColor {
        let key = alpha == 1.0 ? hex : "\(hex)_\(alpha)"
        lock.lock()
        if let cached = cgColorCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let (r, g, b) = Self.parseRGB(from: hex)
        let color = CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)

        lock.lock()
        if cgColorCache.count > 256 { cgColorCache.removeAll(keepingCapacity: true) }
        cgColorCache[key] = color
        lock.unlock()
        return color
    }

    public func nsColor(hex: String, alpha: CGFloat = 1.0) -> NSColor {
        let key = alpha == 1.0 ? hex : "\(hex)_\(alpha)"
        lock.lock()
        if let cached = nsColorCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let (r, g, b) = Self.parseRGB(from: hex)
        let color = NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)

        lock.lock()
        if nsColorCache.count > 256 { nsColorCache.removeAll(keepingCapacity: true) }
        nsColorCache[key] = color
        lock.unlock()
        return color
    }
}

public extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let (r, g, b) = FastColor.parseRGB(from: hex)
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

