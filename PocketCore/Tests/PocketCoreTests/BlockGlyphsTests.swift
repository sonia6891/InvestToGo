import XCTest
@testable import PocketCore

final class BlockGlyphsTests: XCTestCase {
    let W = BlockGlyphs.width, GAP = BlockGlyphs.gap

    func testTwoDigitsUseSevenSegmentBlocks() {
        let result = BlockGlyphs.layout("12")
        XCTAssertEqual(result.blocks.count, 2 + 5, "1 = bc, 2 = abged")
        XCTAssertEqual(result.width, 2 * W + GAP - (W - BlockGlyphs.stroke), accuracy: 1e-9, "Measured on the blocks: the 1 has no left strokes")
        XCTAssertTrue(result.blocks.allSatisfy { $0.shape == .box })
    }
    func testPercentDotAndMinus() {
        let pct = BlockGlyphs.layout("0.42%").blocks
        XCTAssertEqual(pct.filter { $0.shape == .ring }.count, 2)
        XCTAssertEqual(pct.filter { $0.shape == .slash }.count, 1)
        let minus = BlockGlyphs.layout("−0.02%")
        XCTAssertEqual(minus.blocks.first?.shape, .box)
        XCTAssertEqual(minus.blocks.first?.height ?? 0, BlockGlyphs.stroke, accuracy: 1e-9, "The minus is one horizontal bar")
    }
    func testGoldAlternatesPerDigit() {
        let blocks = BlockGlyphs.layout("88").blocks
        XCTAssertEqual(blocks.filter(\.gold).count, 6, "acg on the first digit, bdf on the second")
    }
    func testGlyphLayoutWidthsAndCentering() {
        for text in ["12", "0.42%", "−0.02%", "1240"] {
            let r = BlockGlyphs.layout(text)
            let left = r.blocks.map { $0.x - $0.width / 2 }.min()!, right = r.blocks.map { $0.x + $0.width / 2 }.max()!
            XCTAssertEqual(left, -right, accuracy: 1e-9, text)
            XCTAssertLessThanOrEqual(right - left, r.width + 1e-9, text)
        }
    }
    func testUnknownCharactersAreSkipped() {
        XCTAssertEqual(BlockGlyphs.layout("A1 2").blocks, BlockGlyphs.layout("12").blocks)
        XCTAssertTrue(BlockGlyphs.layout("").blocks.isEmpty)
    }
}
