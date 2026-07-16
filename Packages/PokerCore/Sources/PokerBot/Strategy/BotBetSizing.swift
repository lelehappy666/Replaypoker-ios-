import PokerCore

enum BotBetSizing {
    static func target(
        minimum: Chips,
        maximum: Chips,
        currentCommitment: Chips,
        pot: Chips,
        sizing: Int
    ) throws -> Chips {
        guard (0...100).contains(sizing),
              currentCommitment <= minimum,
              minimum <= maximum
        else {
            throw BotError.invalidObservation
        }

        let (scaledSizing, sizingOverflow) = sizing.multipliedReportingOverflow(by: 67)
        let (basisPoints, basisOverflow) = 3_300.addingReportingOverflow(scaledSizing)
        let (scaledPot, potOverflow) = pot.rawValue.multipliedReportingOverflow(
            by: basisPoints
        )
        let (minimumIncrement, incrementOverflow) = minimum.rawValue
            .subtractingReportingOverflow(currentCommitment.rawValue)
        guard !sizingOverflow, !basisOverflow, !potOverflow, !incrementOverflow,
              minimumIncrement >= 0
        else {
            throw BotError.invalidObservation
        }

        let desiredIncrement = max(minimumIncrement, scaledPot / 10_000)
        let (desired, desiredOverflow) = currentCommitment.rawValue
            .addingReportingOverflow(desiredIncrement)
        guard !desiredOverflow,
              let result = Chips(
                rawValue: min(maximum.rawValue, max(minimum.rawValue, desired))
              )
        else {
            throw BotError.invalidObservation
        }
        return result
    }
}

enum BotAllInEligibility {
    static func isEligible(
        strengthBasisPoints: Int,
        simulatedEquityBasisPoints: Int?,
        effectiveStackBigBlinds: Int,
        potOddsBasisPoints: Int,
        model: BotModel,
        forcedShortCall: Bool
    ) -> Bool {
        if forcedShortCall { return true }
        if effectiveStackBigBlinds <= 12 { return true }
        if strengthBasisPoints >= 8_500 { return true }
        if simulatedEquityBasisPoints.map({ $0 >= 8_000 }) == true { return true }
        return model == .aggressive
            && strengthBasisPoints >= 7_500
            && effectiveStackBigBlinds <= 30
            && potOddsBasisPoints <= 4_000
    }
}
