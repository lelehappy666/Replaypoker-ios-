public struct BotPersonalityOffsets: Codable, Equatable, Sendable {
    public let aggression: Int
    public let bluffFrequency: Int
    public let callingWidth: Int
    public let betSizing: Int

    public init(
        aggression: Int,
        bluffFrequency: Int,
        callingWidth: Int,
        betSizing: Int
    ) {
        precondition(
            [aggression, bluffFrequency, callingWidth, betSizing]
                .allSatisfy { (-5...5).contains($0) }
        )
        self.aggression = aggression
        self.bluffFrequency = bluffFrequency
        self.callingWidth = callingWidth
        self.betSizing = betSizing
    }

    public var values: [Int] {
        [aggression, bluffFrequency, callingWidth, betSizing]
    }

    public func applying(
        to value: Int,
        keyPath: KeyPath<BotPersonalityOffsets, Int>
    ) -> Int {
        min(100, max(0, value + self[keyPath: keyPath]))
    }
}

public enum BotPersonality {
    public static func offsets(
        for stableIdentity: String,
        schemaVersion: Int
    ) -> BotPersonalityOffsets {
        var state: UInt64 = 14_695_981_039_346_656_037
        for byte in stableIdentity.utf8 {
            state ^= UInt64(byte)
            state &*= 1_099_511_628_211
        }
        state ^= UInt64(bitPattern: Int64(schemaVersion))
        state &*= 1_099_511_628_211

        func nextOffset() -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Int(value % 11) - 5
        }

        return BotPersonalityOffsets(
            aggression: nextOffset(),
            bluffFrequency: nextOffset(),
            callingWidth: nextOffset(),
            betSizing: nextOffset()
        )
    }
}
