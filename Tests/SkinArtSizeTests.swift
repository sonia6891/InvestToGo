import XCTest
import UIKit
@testable import ETFToGo

/// The 3D skins' PNGs are quantized when they are exported (Scripts/export_skin_art.py, which also gates the byte
/// total and the PSNR). Quantizing must not change how big each image is drawn.
final class SkinArtSizeTests: XCTestCase {
    /// Edge length in points of each raster image; the PNGs sit in the universal 1x slot.
    private func expectedSide(skin: String, name: SkinArtName) -> CGFloat {
        switch (skin, name) {
        case ("blackgold", .heroDollar), ("blackgold", .pocket), ("blackgold", .pocketIcon): return 1080
        case ("voxel", .heroDollar): return 900
        default: return 720
        }
    }

    func testQuantizedImagesKeepTheirSize() {
        for id in ["blackgold", "voxel"] {
            let skin = Skins.named(id)
            for name in SkinArtName.allCases where name != .badge {  // the badge is a vector
                let image = UIImage(named: skin.art.image(name))
                XCTAssertNotNil(image, "\(id) has no \(name.rawValue)")
                let side = expectedSide(skin: id, name: name)
                XCTAssertEqual(image?.size, CGSize(width: side, height: side), "\(id)/\(name.rawValue) changed size")
            }
        }
    }
}
