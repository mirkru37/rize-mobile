import XCTest
@testable import RizeMobile

final class UUIDv7GeneratorTests: XCTestCase {
    func testGeneratesVersion7Uuids() {
        let generator = UUIDv7Generator(clock: TestClock())
        let uuid = generator.next()

        let versionNibble = uuid.uuid.6 >> 4
        XCTAssertEqual(versionNibble, 0x7)
    }

    func testGeneratesVariantBits() {
        let generator = UUIDv7Generator(clock: TestClock())
        let uuid = generator.next()

        // RFC 9562 variant: top two bits of byte 8 are "10".
        let variantBits = uuid.uuid.8 >> 6
        XCTAssertEqual(variantBits, 0b10)
    }

    func testUuidsAreUnique() {
        let generator = UUIDv7Generator(clock: TestClock())
        var seen = Set<UUID>()

        for _ in 0 ..< 5000 {
            seen.insert(generator.next())
        }

        XCTAssertEqual(seen.count, 5000)
    }

    func testUuidsAreMonotonicallyIncreasingWithinTheSameMillisecond() {
        // Clock frozen: every call happens "at the same instant", which
        // exercises the fixed-length dedicated counter fallback.
        let clock = TestClock()
        let generator = UUIDv7Generator(clock: clock)

        let uuids = (0 ..< 1000).map { _ in generator.next() }

        for (previous, next) in zip(uuids, uuids.dropFirst()) {
            XCTAssertTrue(
                previous.timeOrderingBytes.lexicographicallyPrecedes(next.timeOrderingBytes),
                "expected \(previous) to sort before \(next)"
            )
        }
    }

    func testUuidsAreTimeOrderedAcrossAdvancingClock() {
        let clock = TestClock()
        let generator = UUIDv7Generator(clock: clock)

        var uuids: [UUID] = []
        for _ in 0 ..< 50 {
            uuids.append(generator.next())
            clock.advance(by: 0.01)
        }

        let sortedByTimeOrderingBytes = uuids.sorted {
            $0.timeOrderingBytes.lexicographicallyPrecedes($1.timeOrderingBytes)
        }
        XCTAssertEqual(uuids, sortedByTimeOrderingBytes)
    }
}

private extension UUID {
    /// The first 8 bytes (48-bit timestamp + version/counter), which is the
    /// portion of a UUIDv7 that determines its sort order.
    var timeOrderingBytes: [UInt8] {
        let u = uuid
        return [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7]
    }
}
