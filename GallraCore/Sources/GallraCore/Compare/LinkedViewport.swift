import Foundation
import CoreGraphics

/// Zoom and pan of two compare panes that move together.
///
/// Everything is stored as fractions of the image (0...1), so two photos of different pixel size
/// show the same relative area. `zoom` is relative to "fit in pane" (1 = whole photo visible).
/// Pane 1's centre is pane 0's centre plus `offset`; the offset is non-zero only after a pane was
/// moved on its own, and stays when the panes are linked again.
public struct LinkedViewport: Equatable, Sendable {
    public static let maxZoom = 40.0

    public private(set) var zoom = 1.0
    /// Image point (as a fraction) at the centre of pane 0.
    public private(set) var center = CGPoint(x: 0.5, y: 0.5)
    /// Pane 1's centre minus pane 0's centre.
    public private(set) var offset = CGSize.zero

    public init() {}

    /// Image point (fraction) at the centre of `pane` (0 or 1).
    public func center(forPane pane: Int) -> CGPoint {
        pane == 0 ? center : CGPoint(x: center.x + offset.width, y: center.y + offset.height)
    }

    /// Moves the view of `pane` by `delta` (fractions of the image). Linked: both panes move.
    /// Independent: only that pane moves.
    public mutating func pan(byFraction delta: CGSize, pane: Int, independent: Bool) {
        if pane == 0 {
            center.x += delta.width; center.y += delta.height
            if independent { offset.width -= delta.width; offset.height -= delta.height }
        } else if independent {
            offset.width += delta.width; offset.height += delta.height
        } else {
            center.x += delta.width; center.y += delta.height
        }
    }

    /// Zooms both panes to `newZoom` keeping the image point under `anchor` fixed.
    /// `anchor` is the cursor's distance from the pane centre divided by the pane's fit size.
    public mutating func setZoom(_ newZoom: Double, anchor: CGSize = .zero) {
        let z = min(max(newZoom, 1), LinkedViewport.maxZoom)
        let shift = 1 / zoom - 1 / z
        center.x += anchor.width * shift
        center.y += anchor.height * shift
        zoom = z
    }

    /// Keeps each pane inside its photo. `visible[pane]` is the fraction of the image that the
    /// pane shows per axis (1 or more means the whole axis fits, so it is centred).
    public mutating func clamp(visible: [CGSize]) {
        func limit(_ value: Double, _ visible: Double) -> Double {
            visible >= 1 ? 0.5 : min(max(value, visible / 2), 1 - visible / 2)
        }
        let v0 = visible.first ?? CGSize(width: 1, height: 1)
        let v1 = visible.count > 1 ? visible[1] : v0
        center = CGPoint(x: limit(center.x, v0.width), y: limit(center.y, v0.height))
        let second = center(forPane: 1)
        offset = CGSize(width: limit(second.x, v1.width) - center.x,
                        height: limit(second.y, v1.height) - center.y)
    }

    /// Back to the whole photo in both panes, linked.
    public mutating func reset() { self = LinkedViewport() }
}
