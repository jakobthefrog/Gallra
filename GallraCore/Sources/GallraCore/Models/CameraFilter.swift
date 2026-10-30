import Foundation

/// One number to match exactly, or else a lower and/or upper limit (either end may be open).
public struct NumberRange: Equatable, Sendable {
    /// When set, only this value passes and `min`/`max` are ignored.
    public var exact: Double?
    public var min: Double?
    public var max: Double?

    public init(exact: Double? = nil, min: Double? = nil, max: Double? = nil) {
        self.exact = exact; self.min = min; self.max = max
    }

    public var isActive: Bool { exact != nil || min != nil || max != nil }

    /// A missing value never passes an active range.
    public func contains(_ value: Double?) -> Bool {
        guard isActive else { return true }
        guard let value else { return false }
        if let exact { return abs(value - exact) <= 1e-9 }
        // Small tolerance: shutter and f-number values come from floating-point EXIF fractions.
        if let min, value < min - 1e-9 { return false }
        if let max, value > max + 1e-9 { return false }
        return true
    }
}

/// Which photos pass, by shooting details (aperture, shutter, ISO, focal length).
/// Every active part must match; an empty filter passes everything.
public struct CameraFilter: Equatable, Sendable {
    public var aperture = NumberRange()
    public var shutter = NumberRange()      // seconds
    public var iso = NumberRange()
    public var focalLength = NumberRange()  // mm

    public init() {}

    public var isActive: Bool {
        aperture.isActive || shutter.isActive || iso.isActive || focalLength.isActive
    }

    public func matches(_ info: CameraInfo?) -> Bool {
        guard isActive else { return true }
        guard let info else { return false }
        return aperture.contains(info.aperture) && shutter.contains(info.shutter)
            && iso.contains(info.iso.map(Double.init)) && focalLength.contains(info.focalLength)
    }

    /// Shown in the Filters button when parts are active, e.g. "Filters (2)".
    public var activeCount: Int {
        [aperture.isActive, shutter.isActive, iso.isActive, focalLength.isActive].filter { $0 }.count
    }
}

/// The values found in a folder, to offer as choices in the filter panel.
public struct CameraChoices: Equatable, Sendable {
    public var apertures: [Double] = []
    public var shutters: [Double] = []
    public var isos: [Double] = []
    public var focalLengths: [Double] = []

    public init() {}

    public init(_ infos: some Sequence<CameraInfo>) {
        var apertures = Set<Double>(), shutters = Set<Double>()
        var isos = Set<Double>(), focals = Set<Double>()
        for info in infos {
            if let value = info.aperture { apertures.insert(value) }
            if let value = info.shutter, value > 0 { shutters.insert(value) }
            if let value = info.iso { isos.insert(Double(value)) }
            if let value = info.focalLength { focals.insert(value) }
        }
        self.apertures = apertures.sorted()
        self.shutters = shutters.sorted()
        self.isos = isos.sorted()
        self.focalLengths = focals.sorted()
    }
}
