import XCTest
@testable import PhotoCleanerCore

final class PerceptualHashTests: XCTestCase {
    func testHammingDistanceCountsChangedBits() {
        let lhs = fingerprint(0b1010_0001)
        let rhs = fingerprint(0b1011_1001)

        XCTAssertEqual(lhs.hammingDistance(to: rhs), 2)
    }

    func testNearImagesAreGrouped() {
        let assets = [
            FingerprintedAsset(id: "a", fingerprint: fingerprint(0b1010_0000)),
            FingerprintedAsset(id: "b", fingerprint: fingerprint(0b1010_0001)),
            FingerprintedAsset(id: "c", fingerprint: fingerprint(0b1010_0011))
        ]

        XCTAssertEqual(DuplicateGrouper.groups(from: assets), [["a", "b", "c"]])
    }

    func testIdenticalFingerprintCandidatesAreGrouped() {
        let identical = fingerprint(0xA5A5_A5A5_A5A5_A5A5)
        let assets = [
            FingerprintedAsset(id: "first", fingerprint: identical),
            FingerprintedAsset(id: "second", fingerprint: identical)
        ]

        XCTAssertEqual(DuplicateGrouper.groups(from: assets), [["first", "second"]])
    }

    func testDifferentColorImagesDoNotGroupOnHashAlone() {
        let assets = [
            FingerprintedAsset(id: "warm", fingerprint: fingerprint(0b1010_0000, red: 220, green: 30, blue: 25)),
            FingerprintedAsset(id: "cool", fingerprint: fingerprint(0b1010_0001, red: 10, green: 40, blue: 220))
        ]

        XCTAssertTrue(DuplicateGrouper.groups(from: assets).isEmpty)
    }

    func testBurstAssetsGroupEvenWhenHashesDiffer() {
        let assets = [
            FingerprintedAsset(id: "burst-1", fingerprint: fingerprint(0), burstIdentifier: "burst-x"),
            FingerprintedAsset(id: "burst-2", fingerprint: fingerprint(UInt64.max), burstIdentifier: "burst-x")
        ]

        XCTAssertEqual(DuplicateGrouper.groups(from: assets), [["burst-1", "burst-2"]])
    }

    func testUnrelatedAssetsRemainSeparate() {
        let assets = [
            FingerprintedAsset(id: "a", fingerprint: fingerprint(0)),
            FingerprintedAsset(id: "b", fingerprint: fingerprint(UInt64.max))
        ]

        XCTAssertTrue(DuplicateGrouper.groups(from: assets).isEmpty)
    }

    private func fingerprint(
        _ hash: UInt64,
        red: UInt8 = 100,
        green: UInt8 = 100,
        blue: UInt8 = 100
    ) -> ImageFingerprint {
        ImageFingerprint(differenceHash: hash, red: red, green: green, blue: blue)
    }
}
