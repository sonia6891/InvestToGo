import Foundation
@testable import PocketCore

/// A vector handler takes a case's `input` and returns its output, both as JSONSerialization values.
typealias VectorHandler = (Any) throws -> Any

/// Every shared vector kind Swift answers, keyed by the vector's `kind`.
let vectorHandlers: [String: VectorHandler] = [
    "Vector.echo": { input in try VectorIO.object(input)["value"] ?? NSNull() },
]
