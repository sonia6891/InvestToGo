import XCTest
import Foundation
@testable import PocketCore

/// Runs every shared vector in SharedFixtures/vectors against PocketCore. With RECORD_VECTORS=1 it writes Swift's
/// outputs into each case's `expected` instead of comparing (the format is in SharedFixtures/vectors/README.md).
final class VectorTests: XCTestCase {
    static var root: URL { Fixtures.root.appendingPathComponent("vectors") }
    static var recording: Bool { ProcessInfo.processInfo.environment["RECORD_VECTORS"] == "1" }

    /// Every vector file with its parsed contents: JSON files under vectors/ whose top level has a `kind`.
    static func vectorFiles() throws -> [(url: URL, body: [String: Any])] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: [(url: URL, body: [String: Any])] = []
        for case let url as URL in walker where url.pathExtension == "json" {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
            if let body = object as? [String: Any], body["kind"] is String { found.append((url: url, body: body)) }
        }
        return found.sorted { $0.url.path < $1.url.path }
    }

    static func runsOnSwift(_ body: [String: Any]) -> Bool {
        guard let platforms = body["platforms"] as? [String] else { return true }
        return platforms.contains("swift")
    }

    /// A handler's output, or the error it threw in the vector form.
    static func output(_ handler: VectorHandler, _ input: Any) -> Any {
        do {
            return try handler(input)
        } catch let error as LocalizedError {
            return ["error": error.errorDescription ?? "*"]
        } catch {
            return ["error": "*"]
        }
    }

    func testAllVectors() throws {
        var failures: [String] = []
        for file in try Self.vectorFiles() where Self.runsOnSwift(file.body) {
            let kind = file.body["kind"] as! String
            guard let handler = vectorHandlers[kind] else { continue }
            var cases = file.body["cases"] as? [[String: Any]] ?? []
            for index in cases.indices {
                let name = cases[index]["name"] as? String ?? "#\(index)"
                let actual = Self.output(handler, cases[index]["input"] ?? NSNull())
                if Self.recording {
                    cases[index]["expected"] = actual
                } else if let expected = cases[index]["expected"] {
                    if !VectorJSON.equal(expected, actual) { failures.append("\(kind) / \(name): expected \(expected), got \(actual)") }
                } else {
                    failures.append("\(kind) / \(name): no expected value; record it")
                }
            }
            if Self.recording {
                var next = file.body
                next["cases"] = cases
                let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                try (data + Data("\n".utf8)).write(to: file.url)
            }
        }
        XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testEveryKindHasSwiftHandler() throws {
        let kinds = try Self.vectorFiles().filter { Self.runsOnSwift($0.body) }.map { $0.body["kind"] as! String }
        let missing = kinds.filter { vectorHandlers[$0] == nil }
        XCTAssert(missing.isEmpty, "No Swift handler for: \(missing.joined(separator: ", "))")
    }

    func testNoOrphanSwiftHandler() throws {
        let kinds = Set(try Self.vectorFiles().map { $0.body["kind"] as! String })
        let orphans = vectorHandlers.keys.filter { !kinds.contains($0) }.sorted()
        XCTAssert(orphans.isEmpty, "Handlers without a vector file: \(orphans.joined(separator: ", "))")
    }

    func testVectorJSONEquality() {
        XCTAssertTrue(VectorJSON.equal(1.0, 1))
        XCTAssertTrue(VectorJSON.equal(0.1 + 0.2, 0.3))
        XCTAssertFalse(VectorJSON.equal([1, 2], [2, 1]))
        XCTAssertFalse(VectorJSON.equal(["a": 1], ["a": 1, "b": 2]))
        XCTAssertTrue(VectorJSON.equal(["a": [NSNull(), "x"]], ["a": [NSNull(), "x"]]))
    }
}

/// Equality of JSON values as the README defines it.
enum VectorJSON {
    static func equal(_ a: Any, _ b: Any) -> Bool {
        if a is NSNull || b is NSNull { return a is NSNull && b is NSNull }
        if let x = a as? String { return (b as? String) == x }
        if let x = a as? [Any] {
            guard let y = b as? [Any], x.count == y.count else { return false }
            return zip(x, y).allSatisfy { equal($0, $1) }
        }
        if let x = a as? [String: Any] {
            guard let y = b as? [String: Any], Set(x.keys) == Set(y.keys) else { return false }
            return x.allSatisfy { key, value in equal(value, y[key]!) }
        }
        // Numbers and booleans: Foundation on Linux hands both back as NSNumber, so true and 1 compare equal here; the
        // Kotlin reader keeps them apart.
        guard let x = number(a), let y = number(b) else { return false }
        return abs(x - y) <= max(1e-9, 1e-12 * max(abs(x), abs(y)))
    }

    private static func number(_ value: Any) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let b = value as? Bool { return b ? 1 : 0 }
        return nil
    }
}

/// Helpers for handlers: JSON values in and out through Codable, and the vector's time format.
enum VectorIO {
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }

    static func encode<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }

    static func date(_ text: String) throws -> Date {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: text) { return d }
        throw AppDataError("bad vector date \(text)")
    }

    static func object(_ value: Any) throws -> [String: Any] {
        guard let o = value as? [String: Any] else { throw AppDataError("vector input is not an object") }
        return o
    }

    /// The bytes of a `{"file": path}` input, relative to SharedFixtures.
    static func file(_ value: Any) throws -> Data {
        guard let path = (value as? [String: Any])?["file"] as? String else { throw AppDataError("vector input has no file") }
        return try Fixtures.data(path)
    }
}
