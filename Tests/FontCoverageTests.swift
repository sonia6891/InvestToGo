import XCTest
import CoreText
@testable import ETFToGo

/// The bundled fonts are subset to the app's own text (Scripts/subset_fonts.py). Every CJK character the app can show
/// from the bundled catalogue and the skin copy must still be in the fonts that draw it.
final class FontCoverageTests: XCTestCase {
    /// DotGothic16 is a Japanese font; Chinese characters it never had fall back to the system font, as before.
    private let exempt: Set<String> = ["DotGothic16-Regular"]

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
            || (0x20000...0x3FFFF).contains(scalar.value)
    }

    private func cjk(_ text: String) -> Set<Unicode.Scalar> {
        Set(text.precomposedStringWithCanonicalMapping.unicodeScalars.filter(isCJK))
    }

    /// Characters of `wanted` that `fontName` has no glyph for.
    private func missing(_ wanted: Set<Unicode.Scalar>, in fontName: String) -> String {
        let set = CTFontCopyCharacterSet(CTFontCreateWithName(fontName as CFString, 17, nil)) as CharacterSet
        return String(String.UnicodeScalarView(wanted.filter { !set.contains($0) }.sorted { $0.value < $1.value }))
    }

    private func assertCovered(_ wanted: Set<Unicode.Scalar>, what: String) {
        XCTAssertFalse(wanted.isEmpty, "\(what) has no CJK characters to check")
        for skin in Skins.all {
            for name in [skin.fonts.title, skin.fonts.body] where !exempt.contains(name) {
                let gone = missing(wanted, in: name)
                XCTAssertEqual(gone, "", "\(skin.id): font \(name) lacks \(gone.count) characters of \(what): \(gone)")
            }
        }
    }

    func testCatalogNamesAreCovered() throws {
        let catalog = try XCTUnwrap(CatalogSnapshot.bundled())
        var wanted = Set<Unicode.Scalar>()
        for fund in catalog.funds { wanted.formUnion(cjk(fund.name)); wanted.formUnion(cjk(fund.fullName ?? "")) }
        assertCovered(wanted, what: "the catalogue fund names")
    }

    func testSkinNamesAreCovered() {
        var wanted = Set<Unicode.Scalar>()
        for skin in Skins.all { wanted.formUnion(cjk(skin.name)); wanted.formUnion(cjk(skin.code)) }
        assertCovered(wanted, what: "the skin names and codes")
    }
}
