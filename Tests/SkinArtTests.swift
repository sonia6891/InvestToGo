import XCTest
import UIKit
@testable import ETFToGo

/// Every skin's art and fonts must ship in the app, under the names screens ask for.
final class SkinArtTests: XCTestCase {
    /// Images only some skins carry: numerals for the vector skins, plus stitch's mustard set and cloth patch,
    /// and sketch's tally marks.
    private func extraNames(_ skin: Skin) -> [String] {
        guard skin.art.kind == .vector else { return [] }
        var names = (0...9).map { "digit_\($0)" }
        if skin.id == "stitch" { names += (0...9).map { "digit_\($0)_b" } + ["patch"] }
        if skin.id == "sketch" { names += (1...5).map { "tally_\($0)" } }
        return names
    }

    func testEveryNamedImageExistsForEverySkin() {
        XCTAssertEqual(Skins.all.count, 4)
        for skin in Skins.all {
            for name in SkinArtName.allCases {
                XCTAssertNotNil(UIImage(named: skin.art.image(name)), "\(skin.id) has no \(name.rawValue)")
            }
            for name in extraNames(skin) {
                XCTAssertNotNil(UIImage(named: skin.art.image(named: name)), "\(skin.id) has no \(name)")
            }
        }
        XCTAssertEqual(extraNames(Skins.named("stitch")).count, 21)
        XCTAssertEqual(extraNames(Skins.named("sketch")).count, 15)
    }

    func testFontsAreRegistered() {
        for skin in Skins.all {
            for name in [skin.fonts.big, skin.fonts.title, skin.fonts.body, skin.fonts.mono] {
                XCTAssertNotNil(UIFont(name: name, size: 17), "\(skin.id) font \(name) is not registered")
            }
        }
    }
}
