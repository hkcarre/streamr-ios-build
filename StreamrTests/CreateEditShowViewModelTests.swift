import UIKit
import XCTest
@testable import Streamr

/// Exercises CreateEditShowViewModel.validateArtwork directly — a pure
/// function, so these run fully offline with synthetic dimensions rather
/// than needing to drive a real PhotosPickerItem.
final class CreateEditShowViewModelTests: XCTestCase {
    func testSquareInRangeUnderSizeLimitPasses() {
        let error = CreateEditShowViewModel.validateArtwork(
            pixelWidth: 2000, pixelHeight: 2000, jpegByteCount: 1_000_000
        )
        XCTAssertNil(error)
    }

    func testExactBoundariesPass() {
        XCTAssertNil(CreateEditShowViewModel.validateArtwork(pixelWidth: 1400, pixelHeight: 1400, jpegByteCount: 2 * 1024 * 1024))
        XCTAssertNil(CreateEditShowViewModel.validateArtwork(pixelWidth: 3000, pixelHeight: 3000, jpegByteCount: 1))
    }

    func testNonSquareFails() {
        let error = CreateEditShowViewModel.validateArtwork(
            pixelWidth: 1400, pixelHeight: 1600, jpegByteCount: 1_000_000
        )
        XCTAssertEqual(error, "Cover art must be a square image.")
    }

    func testTooSmallFails() {
        let error = CreateEditShowViewModel.validateArtwork(
            pixelWidth: 999, pixelHeight: 999, jpegByteCount: 1_000_000
        )
        XCTAssertEqual(error, "Cover art must be between 1400 and 3000 pixels per side.")
    }

    func testTooLargeDimensionsFails() {
        let error = CreateEditShowViewModel.validateArtwork(
            pixelWidth: 3200, pixelHeight: 3200, jpegByteCount: 1_000_000
        )
        XCTAssertEqual(error, "Cover art must be between 1400 and 3000 pixels per side.")
    }

    func testOverFileSizeLimitFails() {
        let error = CreateEditShowViewModel.validateArtwork(
            pixelWidth: 2000, pixelHeight: 2000, jpegByteCount: 2 * 1024 * 1024 + 1
        )
        XCTAssertEqual(error, "Cover art file is too large — must be 2MB or smaller.")
    }

    /// processArtwork replaced validateArtwork as the actual production
    /// path (any picked photo is auto-cropped/resized instead of being
    /// rejected) — this checks the output always satisfies the same
    /// constraint validateArtwork documents, for a deliberately awkward
    /// non-square, out-of-range input.
    func testProcessArtworkAlwaysProducesValidSquare() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 500)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 500))
        }

        let processed = try XCTUnwrap(CreateEditShowViewModel.processArtwork(source))

        XCTAssertEqual(processed.image.size.width, processed.image.size.height)
        XCTAssertNil(CreateEditShowViewModel.validateArtwork(
            pixelWidth: processed.image.size.width,
            pixelHeight: processed.image.size.height,
            jpegByteCount: processed.jpegData.count
        ))
    }
}
