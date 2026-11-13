import Foundation

/// Loads files from the repository's SharedFixtures directory (shared with the future Android app).
enum Fixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("SharedFixtures")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        fatalError("SharedFixtures directory not found above \(#filePath)")
    }()
    static func data(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }
}
