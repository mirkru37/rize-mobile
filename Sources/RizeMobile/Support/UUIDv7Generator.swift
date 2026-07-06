import Foundation

/// Generates client-side identifiers per [[sync-protocol]]'s idempotency rule:
/// every client-created record carries a client-generated **UUIDv7**, which is
/// both globally unique and time-ordered, so retries of a failed/ambiguous
/// upload can never create duplicate rows.
///
/// Implements RFC 9562's "Fixed-Length Dedicated Counter" monotonic method
/// (section 6.2, method 1): the 12 bits of `rand_a` are used as a counter
/// that increments whenever two UUIDs are generated within the same
/// millisecond, guaranteeing strictly increasing values even under bursts,
/// rather than relying on randomness alone for ordering.
public final class UUIDv7Generator: @unchecked Sendable {
    private let clock: Clock
    private let lock = NSLock()
    private var lastTimestampMs: UInt64 = 0
    private var counter: UInt32 = 0

    public init(clock: Clock = SystemClock()) {
        self.clock = clock
    }

    /// Generates a new time-ordered UUIDv7.
    public func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }

        let nowMs = UInt64(max(0, clock.now().timeIntervalSince1970 * 1000))

        if nowMs > lastTimestampMs {
            lastTimestampMs = nowMs
            counter = UInt32.random(in: 0 ... 0xFFF)
        } else {
            counter += 1
            if counter > 0xFFF {
                // Counter space for this millisecond is exhausted; borrow the
                // next millisecond so ordering stays strictly monotonic.
                lastTimestampMs += 1
                counter = 0
            }
        }

        return Self.build(timestampMs: lastTimestampMs, counter: counter)
    }

    private static func build(timestampMs: UInt64, counter: UInt32) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        bytes[0] = UInt8((timestampMs >> 40) & 0xFF)
        bytes[1] = UInt8((timestampMs >> 32) & 0xFF)
        bytes[2] = UInt8((timestampMs >> 24) & 0xFF)
        bytes[3] = UInt8((timestampMs >> 16) & 0xFF)
        bytes[4] = UInt8((timestampMs >> 8) & 0xFF)
        bytes[5] = UInt8(timestampMs & 0xFF)

        // Byte 6: version (0111) in the high nibble, top 4 bits of the
        // 12-bit counter (rand_a) in the low nibble.
        bytes[6] = 0x70 | UInt8((counter >> 8) & 0x0F)
        // Byte 7: low 8 bits of the counter.
        bytes[7] = UInt8(counter & 0xFF)

        // Bytes 8...15: rand_b (62 random bits), with the variant (10) in
        // the top two bits of byte 8 per RFC 9562.
        var randomTail = [UInt8](repeating: 0, count: 8)
        for i in 0 ..< 8 {
            randomTail[i] = UInt8.random(in: 0 ... 255)
        }
        randomTail[0] = (randomTail[0] & 0x3F) | 0x80

        for i in 0 ..< 8 {
            bytes[8 + i] = randomTail[i]
        }

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
