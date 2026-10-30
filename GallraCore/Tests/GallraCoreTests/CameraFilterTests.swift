import Testing
@testable import GallraCore

@Suite struct CameraFilterTests {
    let portrait = CameraInfo(lens: "RF 85mm", aperture: 1.8, shutter: 1.0 / 200, iso: 100, focalLength: 85)
    let wide = CameraInfo(lens: "RF 24-70mm", aperture: 8, shutter: 1.0 / 60, iso: 800, focalLength: 24)

    @Test func emptyFilterPassesEverythingEvenUnknown() {
        let filter = CameraFilter()
        #expect(!filter.isActive)
        #expect(filter.matches(nil) && filter.matches(CameraInfo()))
    }

    @Test func exactValueMatchesOnlyThatValue() {
        var filter = CameraFilter()
        filter.aperture = NumberRange(exact: 1.8)
        #expect(filter.matches(portrait) && !filter.matches(wide))
        filter.aperture = NumberRange(exact: 2.8)
        #expect(!filter.matches(portrait))
        // exact wins over a range
        filter.aperture = NumberRange(exact: 8, min: 1, max: 2)
        #expect(filter.matches(wide))
    }

    @Test func rangesCombine() {
        var filter = CameraFilter()
        filter.aperture = NumberRange(max: 2.8)
        filter.iso = NumberRange(min: 50, max: 400)
        #expect(filter.matches(portrait))
        filter.iso = NumberRange(min: 200)
        #expect(!filter.matches(portrait))
        #expect(filter.activeCount == 2)
    }

    @Test func missingValuesFailActiveFilters() {
        var filter = CameraFilter()
        filter.focalLength = NumberRange(min: 50)
        #expect(!filter.matches(nil))
        #expect(!filter.matches(CameraInfo(lens: "x")))
    }

    @Test func shutterRangeUsesSeconds() {
        var filter = CameraFilter()
        filter.shutter = NumberRange(max: 1.0 / 100)   // 1/100 s or faster
        #expect(filter.matches(portrait) && !filter.matches(wide))
    }

    @Test func choicesAreSortedAndUnique() {
        let choices = CameraChoices([wide, portrait, portrait])
        #expect(choices.apertures == [1.8, 8] && choices.isos == [100, 800])
    }
}
