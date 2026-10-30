import Testing
import CoreGraphics
@testable import GallraCore

@Suite struct LinkedViewportTests {
    private let full = [CGSize(width: 1, height: 1), CGSize(width: 1, height: 1)]

    @Test func linkedPanMovesBothPanesEqually() {
        var vp = LinkedViewport()
        vp.setZoom(4)
        vp.pan(byFraction: CGSize(width: 0.1, height: -0.05), pane: 1, independent: false)
        #expect(abs(vp.center(forPane: 0).x - 0.6) < 1e-9)
        #expect(abs(vp.center(forPane: 1).x - 0.6) < 1e-9)
        #expect(abs(vp.center(forPane: 1).y - 0.45) < 1e-9)
    }

    @Test func independentPanMovesOnlyOnePaneAndRelinksAtOffset() {
        var vp = LinkedViewport()
        vp.setZoom(4)
        vp.pan(byFraction: CGSize(width: 0.1, height: 0), pane: 0, independent: true)
        #expect(abs(vp.center(forPane: 0).x - 0.6) < 1e-9)
        #expect(abs(vp.center(forPane: 1).x - 0.5) < 1e-9)
        // linked again: both move together, the 0.1 gap stays
        vp.pan(byFraction: CGSize(width: 0.05, height: 0), pane: 1, independent: false)
        #expect(abs(vp.center(forPane: 0).x - 0.65) < 1e-9)
        #expect(abs(vp.center(forPane: 1).x - 0.55) < 1e-9)
    }

    @Test func zoomKeepsPointUnderCursorFixed() {
        var vp = LinkedViewport()
        vp.setZoom(2)
        let anchor = CGSize(width: 0.2, height: -0.1)
        // image point under cursor before: c + a/z
        let before = vp.center.x + anchor.width / vp.zoom
        vp.setZoom(5, anchor: anchor)
        let after = vp.center.x + anchor.width / vp.zoom
        #expect(abs(before - after) < 1e-9)
    }

    @Test func zoomIsLimited() {
        var vp = LinkedViewport()
        vp.setZoom(0.2); #expect(vp.zoom == 1)
        vp.setZoom(1000); #expect(vp.zoom == LinkedViewport.maxZoom)
    }

    @Test func clampKeepsViewInsidePhotoAndCentresWhenFitted() {
        var vp = LinkedViewport()
        vp.setZoom(4)
        vp.pan(byFraction: CGSize(width: 5, height: -5), pane: 0, independent: false)
        let v = CGSize(width: 0.25, height: 0.25)
        vp.clamp(visible: [v, v])
        #expect(abs(vp.center.x - 0.875) < 1e-9)
        #expect(abs(vp.center.y - 0.125) < 1e-9)
        vp.setZoom(1)
        vp.clamp(visible: full)
        #expect(vp.center == CGPoint(x: 0.5, y: 0.5))
    }
}
