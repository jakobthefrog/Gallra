import Foundation

/// Makes a scratch folder holding COPIES of the sample photos. Originals are never touched.
enum Scratch {
    static let samples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Gallra-TestPhotos")

    /// New temp folder with copies of up to `cr3` CR3 and `threeFR` 3FR samples.
    static func folder(cr3: Int = 2, threeFR: Int = 2) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: samples.path).sorted()
        for (ext, count) in [("cr3", cr3), ("3fr", threeFR)] {
            for name in names.filter({ $0.lowercased().hasSuffix(ext) }).prefix(count) {
                try FileManager.default.copyItem(at: samples.appendingPathComponent(name),
                                                 to: dir.appendingPathComponent(name))
            }
        }
        return dir
    }
}
