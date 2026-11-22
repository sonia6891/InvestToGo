import Foundation
@testable import PocketCore

/// A vector handler takes a case's `input` and returns its output, both as JSONSerialization values.
typealias VectorHandler = (Any) throws -> Any

/// Every shared vector kind Swift answers, keyed by the vector's `kind`.
let vectorHandlers: [String: VectorHandler] = [
    ["Vector.echo": { input in try VectorIO.object(input)["value"] ?? NSNull() }],
    supportHandlers,
    modelHandlers,
    sourceHandlers,
    gameHandlers,
    analyticsHandlers,
    importHandlers,
    designHandlers,
].reduce(into: [:]) { all, group in all.merge(group) { first, _ in first } }

/// `nil` as JSON null.
func orNull(_ value: Any?) -> Any { value ?? NSNull() }

func string(_ input: Any, _ key: String) throws -> String {
    guard let value = try VectorIO.object(input)[key] as? String else { throw AppDataError("vector input has no \(key)") }
    return value
}

func number(_ input: Any, _ key: String) throws -> Double {
    guard let value = try VectorIO.object(input)[key] as? NSNumber else { throw AppDataError("vector input has no \(key)") }
    return value.doubleValue
}

func at(_ input: Any, _ key: String = "at") throws -> Date { try VectorIO.date(string(input, key)) }

let supportHandlers: [String: VectorHandler] = [
    "DataChecks.code": { input in DataChecks.code(try string(input, "value")) },
    "DataChecks.rocDay": { input in orNull(DataChecks.rocDay(try string(input, "text"))) },
    "DataChecks.date": { input in orNull(DataChecks.date(try string(input, "text"))?.timeIntervalSince1970) },
    "DataChecks.day": { input in DataChecks.day(try at(input)) },
    "StableID.make": { input in StableID.make(try string(input, "namespace"), try string(input, "value")).uuidString },
    "SHA256Digest.hash": { input in
        SHA256Digest.hash(Data(try string(input, "utf8").utf8)).map { String(format: "%02x", $0) }.joined()
    },
    "TaiwanMarket.isOpen": { input in TaiwanMarket.isOpen(try at(input)) },
    "TrendRole.init": { input in
        let role = TrendRole(try number(input, "value"))
        let name: String
        switch role { case .up: name = "up"; case .down: name = "down"; case .flat: name = "flat" }
        return ["role": name, "colorName": role.colorName]
    },
]
