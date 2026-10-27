import XCTest
@testable import Drivy

/// The nonce pair is security relevant: Apple signs the SHA256 hash, Supabase
/// verifies the raw value, so both helpers are pinned here.
final class AppleNonceTests: XCTestCase {

    func testSHA256HexMatchesKnownDigests() {
        XCTAssertEqual(
            AppleNonce.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            AppleNonce.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testRandomUsesDefaultLengthAndAllowedCharset() {
        let nonce = AppleNonce.random()

        XCTAssertEqual(nonce.count, 32)
        for character in nonce {
            XCTAssertTrue(
                AppleNonce.charset.contains(character),
                "nonce contains a character outside the allowed charset: \(character)"
            )
        }
    }

    func testRandomHonoursRequestedLength() {
        XCTAssertEqual(AppleNonce.random(length: 48).count, 48)
        XCTAssertEqual(AppleNonce.random(length: 0), "")
    }

    func testRandomIsNotRepeated() {
        XCTAssertNotEqual(AppleNonce.random(), AppleNonce.random())
    }
}
