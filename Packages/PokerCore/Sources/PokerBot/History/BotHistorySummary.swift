public struct BotHistorySummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let opponentFoldBasisPoints: Int
    public let opponentAggressionBasisPoints: Int

    public init(
        sampleCount: Int,
        opponentFoldBasisPoints: Int,
        opponentAggressionBasisPoints: Int
    ) {
        self.sampleCount = max(0, sampleCount)
        self.opponentFoldBasisPoints = min(10_000, max(0, opponentFoldBasisPoints))
        self.opponentAggressionBasisPoints = min(
            10_000,
            max(0, opponentAggressionBasisPoints)
        )
    }
}
