import Testing
import Foundation
@testable import GallraCore

@Suite struct SceneClustererTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func similarShotsCloseInTimeShareAScene() {
        let r = SceneClusterer.cluster(times: [at(0), at(2), at(4)], distance: { _, _ in 0.1 })
        #expect(r == [0, 0, 0])
    }

    @Test func longPauseSplitsEvenIfSimilar() {
        let r = SceneClusterer.cluster(times: [at(0), at(2), at(200)], distance: { _, _ in 0.1 })
        #expect(r == [0, 0, 1])
    }

    @Test func visualChangeSplitsEvenIfFast() {
        let r = SceneClusterer.cluster(times: [at(0), at(1), at(2)], distance: { i, _ in i == 1 ? Float(5) : Float(0.1) })
        #expect(r == [0, 0, 1])
    }

    @Test func unknownDistanceIsConservative() {
        let r = SceneClusterer.cluster(times: [at(0), at(1)], distance: { _, _ in nil })
        #expect(r == [0, 1])
    }

    @Test func missingTimesFallBackToLooks() {
        let r = SceneClusterer.cluster(times: [nil, nil, nil], distance: { i, _ in i == 0 ? Float(0.1) : Float(5) })
        #expect(r == [0, 0, 1])
    }
}
