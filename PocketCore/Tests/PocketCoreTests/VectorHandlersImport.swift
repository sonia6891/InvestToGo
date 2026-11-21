import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import PocketCore

// Broker CSV and screenshot import: the shapes both platforms read and write in SharedFixtures/vectors/importing.

private func funds(_ input: Any) throws -> [Fund] {
    guard let list = try VectorIO.object(input)["funds"] else { return Fund.starters }
    return try VectorIO.decode([Fund].self, list)
}

private func mapping(_ input: Any, _ table: CSVTable) throws -> BrokerMapping {
    guard let m = try VectorIO.object(input)["mapping"] else { return BrokerMapping(guessing: table) }
    return BrokerMapping(symbol: try int(m, "symbol"), name: try int(m, "name"), shares: try int(m, "shares"), cost: try int(m, "cost"),
                         lots: (try VectorIO.object(m)["lots"] as? Bool) ?? false, totalCost: (try VectorIO.object(m)["totalCost"] as? Bool) ?? true)
}

private func mappingOutput(_ m: BrokerMapping) -> [String: Any] {
    ["symbol": m.symbol, "name": m.name, "shares": m.shares, "cost": m.cost, "lots": m.lots, "totalCost": m.totalCost]
}

private func previewOutput(_ p: BrokerPreview) throws -> [String: Any] {
    ["holdings": try p.holdings.map { try VectorIO.encode($0) }, "sourceAccount": p.sourceAccount, "broker": p.broker,
     "skipped": p.skipped, "skippedCodes": p.skippedCodes.sorted(), "totalCost": p.totalCost]
}

private func optionalNumber(_ object: [String: Any], _ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }

private func draft(_ value: Any) throws -> ScreenshotImport.Draft {
    let object = try VectorIO.object(value)
    var d = ScreenshotImport.Draft()
    d.symbol = try string(value, "symbol"); d.shares = try string(value, "shares"); d.cost = try string(value, "cost")
    d.perShare = (object["perShare"] as? Bool) ?? false
    d.kind = try kind(object["kind"] as? String ?? "現股")
    return d
}

private func drafts(_ input: Any) throws -> [ScreenshotImport.Draft] {
    guard let list = try VectorIO.object(input)["drafts"] as? [Any] else { throw AppDataError("vector input has no drafts") }
    return try list.map(draft)
}

private func kind(_ raw: String) throws -> ScreenshotImport.Kind {
    guard let kind = ScreenshotImport.Kind(rawValue: raw) else { throw AppDataError("unknown kind") }
    return kind
}

private func basisName(_ basis: ScreenshotImport.Basis?) -> Any {
    switch basis { case .total: return "total"; case .perShare: return "perShare"; case nil: return NSNull() }
}

private func row(_ value: Any) throws -> ScreenshotImport.Row {
    let object = try VectorIO.object(value)
    var r = ScreenshotImport.Row(symbol: try string(value, "symbol"))
    r.shares = optionalNumber(object, "shares"); r.cost = optionalNumber(object, "cost")
    r.name = object["name"] as? String; r.choices = object["choices"] as? [String] ?? []; r.note = object["note"] as? String
    r.kind = try kind(object["kind"] as? String ?? "現股")
    switch object["basis"] as? String { case "total": r.basis = .total; case "perShare": r.basis = .perShare; default: r.basis = nil }
    return r
}

private func rowOutput(_ r: ScreenshotImport.Row) -> [String: Any] {
    ["symbol": r.symbol, "shares": orNull(r.shares), "cost": orNull(r.cost), "name": orNull(r.name), "choices": r.choices,
     "note": orNull(r.note), "kind": r.kind.rawValue, "basis": basisName(r.basis)]
}

private func boxes(_ input: Any, _ key: String) throws -> [(text: String, box: CGRect)] {
    guard let list = try VectorIO.object(input)[key] as? [Any] else { throw AppDataError("vector input has no \(key)") }
    return try list.map { item in
        guard let b = try VectorIO.object(item)["box"] as? [NSNumber], b.count == 4 else { throw AppDataError("box is not four numbers") }
        return (text: try string(item, "text"), box: CGRect(x: b[0].doubleValue, y: b[1].doubleValue, width: b[2].doubleValue, height: b[3].doubleValue))
    }
}

private func listing(_ value: Any) throws -> ScreenshotImport.Listing {
    guard let entries = value as? [[String]] else { throw AppDataError("listing is not pairs") }
    return ScreenshotImport.Listing(entries.map { (code: $0[0], name: $0[1]) })
}

private func preview(_ input: Any) throws -> BrokerPreview {
    let object = try VectorIO.object(input)
    if object["drafts"] != nil {
        return try BrokerPreview.make(drafts: drafts(input), broker: string(input, "broker"), account: string(input, "account"), funds: funds(input))
    }
    let table = try CSVTable.parse(inputBytes(input))
    return try BrokerPreview.make(table: table, mapping: mapping(input, table), broker: string(input, "broker"), account: string(input, "account"), funds: funds(input))
}

let importHandlers: [String: VectorHandler] = [
    "CSVTable.parse": { input in
        let table = try CSVTable.parse(inputBytes(input))
        return ["headers": table.headers, "rows": table.rows]
    },
    "BrokerMapping.guessing": { input in mappingOutput(BrokerMapping(guessing: try CSVTable.parse(inputBytes(input)))) },
    "BrokerPreview.makeTable": { input in try previewOutput(preview(input)) },
    "BrokerPreview.makeDrafts": { input in try previewOutput(preview(input)) },
    "BrokerPreview.warnings": { input in
        let prices = try VectorIO.object(input)["prices"] as? [String: NSNumber] ?? [:]
        return try preview(input).warnings(price: { prices[$0]?.doubleValue })
    },
    "BrokerPreview.costWarning": { input in
        orNull(BrokerPreview.costWarning(average: try number(input, "average"), price: optionalNumber(try VectorIO.object(input), "price")))
    },
    "BrokerPreview.shareCount": { input in orNull(BrokerPreview.shareCount(try string(input, "text"))) },
    "BrokerPreview.number": { input in
        guard let value = BrokerPreview.number(try string(input, "text")) else { return NSNull() }
        // JSON has no NaN or infinity: they are written as text.
        if value.isNaN { return "nan" }
        if value.isInfinite { return value > 0 ? "inf" : "-inf" }
        return value
    },
    "ScreenshotImport.lines": { input in ScreenshotImport.lines(from: try boxes(input, "boxes")) },
    "ScreenshotImport.combine": { input in
        ScreenshotImport.combine(corrected: try boxes(input, "corrected"), raw: try boxes(input, "raw")).map {
            ["text": $0.text, "box": [$0.box.origin.x, $0.box.origin.y, $0.box.size.width, $0.box.size.height].map { Double($0) }] as [String: Any]
        }
    },
    "ScreenshotImport.parse": { input in
        guard let lines = try VectorIO.object(input)["lines"] as? [String] else { throw AppDataError("vector input has no lines") }
        return ScreenshotImport.parse(lines, in: try listing(try value(input, "listing"))).map(rowOutput)
    },
    "ScreenshotImport.review": { input in
        guard let pages = try VectorIO.object(input)["pages"] as? [[Any]] else { throw AppDataError("vector input has no pages") }
        let result = ScreenshotImport.review(try pages.map { try $0.map(row) })
        return ["rows": result.rows.map(rowOutput), "short": result.short.map(rowOutput)]
    },
    "ScreenshotImport.basis": { input in
        basisName(ScreenshotImport.basis(cost: try number(input, "cost"), shares: try number(input, "shares"), price: optionalNumber(try VectorIO.object(input), "price")))
    },
    "ScreenshotImport.plausible": { input in ScreenshotImport.plausible(try number(input, "average"), try number(input, "price")) },
    "ScreenshotImport.Draft": { input in
        let d = ScreenshotImport.Draft(try row(try value(input, "row")), price: optionalNumber(try VectorIO.object(input), "price"))
        return ["symbol": d.symbol, "shares": d.shares, "cost": d.cost, "perShare": d.perShare, "kind": d.kind.rawValue, "seen": d.seen,
                "choices": d.choices, "note": orNull(d.note), "costNote": orNull(d.costNote), "totalCost": orNull(d.totalCost), "averageCost": orNull(d.averageCost)] as [String: Any]
    },
    "ScreenshotImport.Listing": { input in
        let l = try listing(try value(input, "entries"))
        let object = try VectorIO.object(input)
        return ["exact": (object["exact"] as? [String] ?? []).map { l.exact($0) }, "near": (object["near"] as? [String] ?? []).map { l.near($0) },
                "knows": (object["knows"] as? [String] ?? []).map { l.knows($0) }] as [String: Any]
    },
]
