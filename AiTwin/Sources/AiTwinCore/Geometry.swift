import Foundation

/// A point in AppKit's coordinate space: origin bottom-left, +y is up.
///
/// Core deliberately uses its own value types rather than CoreGraphics ones so
/// that this module stays importable on a platform without CoreGraphics.
public struct GPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct GRect: Equatable, Sendable {
    public var origin: GPoint
    public var size: GSize

    public init(origin: GPoint, size: GSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: GPoint(x: x, y: y), size: GSize(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
}
