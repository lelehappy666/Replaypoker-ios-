import Foundation
import PokerCore

public enum CashSessionPhase: String, Codable, Equatable, Sendable {
    case readyForHand
    case handInProgress
    case settlementPending
    case left

    public static var readyForNextHand: Self { .readyForHand }
}

public struct CashSessionView: Codable, Equatable, Sendable {
    public let id: SessionID
    public let table: TableID
    public let humanSeat: SeatID
    public let phase: CashSessionPhase
    public let dealer: SeatID
    public let completedHands: Int
    public let seats: [CashSeatView]
    public let currentActor: SeatID?

    public init(
        id: SessionID,
        table: TableID,
        humanSeat: SeatID,
        phase: CashSessionPhase,
        dealer: SeatID,
        completedHands: Int,
        seats: [CashSeatView],
        currentActor: SeatID?
    ) {
        self.id = id
        self.table = table
        self.humanSeat = humanSeat
        self.phase = phase
        self.dealer = dealer
        self.completedHands = completedHands
        self.seats = seats
        self.currentActor = currentActor
    }
}

public struct CashSeatView: Codable, Equatable, Sendable {
    public let id: SeatID
    public let stack: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool

    public init(id: SeatID, stack: Chips, hasFolded: Bool, isAllIn: Bool) {
        self.id = id
        self.stack = stack
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
    }
}

package struct PendingCashHand: Codable, Equatable, Sendable {
    package let id: HandID
    package let startedAt: Date
    package let record: CompletedHandRecord
}

package struct CashGameSession: Codable, Equatable, Sendable {
    package let id: SessionID
    package let table: TableID
    package let humanSeat: SeatID
    package var config: HandConfig
    package var phase: CashSessionPhase
    package var completedHands: Int
    package var stacks: [SeatID: Chips]
    package var checkpoint: HoldemCheckpoint?
    package var pendingHand: PendingCashHand?
    package var activeHandID: HandID?
    package var activeHandStartedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, table, humanSeat, config, phase, completedHands, stacks
        case checkpoint, pendingHand, activeHandID, activeHandStartedAt
    }

    private init(
        id: SessionID,
        table: TableID,
        humanSeat: SeatID,
        config: HandConfig,
        phase: CashSessionPhase,
        completedHands: Int,
        stacks: [SeatID: Chips],
        checkpoint: HoldemCheckpoint?,
        pendingHand: PendingCashHand?,
        activeHandID: HandID?,
        activeHandStartedAt: Date?
    ) {
        self.id = id
        self.table = table
        self.humanSeat = humanSeat
        self.config = config
        self.phase = phase
        self.completedHands = completedHands
        self.stacks = stacks
        self.checkpoint = checkpoint
        self.pendingHand = pendingHand
        self.activeHandID = activeHandID
        self.activeHandStartedAt = activeHandStartedAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SessionID.self, forKey: .id)
        table = try container.decode(TableID.self, forKey: .table)
        humanSeat = try container.decode(SeatID.self, forKey: .humanSeat)
        config = try container.decode(HandConfig.self, forKey: .config)
        phase = try container.decode(CashSessionPhase.self, forKey: .phase)
        completedHands = try container.decode(Int.self, forKey: .completedHands)
        stacks = try container.decode([SeatID: Chips].self, forKey: .stacks)
        checkpoint = try container.decodeIfPresent(HoldemCheckpoint.self, forKey: .checkpoint)
        pendingHand = try container.decodeIfPresent(PendingCashHand.self, forKey: .pendingHand)
        activeHandID = try container.decodeIfPresent(HandID.self, forKey: .activeHandID)
        activeHandStartedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .activeHandStartedAt
        )

        do {
            try validateRestoredState()
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid cash session snapshot",
                    underlyingError: error
                )
            )
        }
    }

    package static func make(
        id: SessionID,
        table: TableID,
        config: HandConfig,
        humanSeat: SeatID,
        stacks: [SeatID: Chips]
    ) throws -> Self {
        try validateTable(stacks: stacks, humanSeat: humanSeat)
        guard stacks[config.dealer] != nil else {
            throw PokerSessionError.invalidTable
        }
        try validateHumanBuyIn(stacks[humanSeat]!, bigBlind: config.bigBlind)

        return Self(
            id: id,
            table: table,
            humanSeat: humanSeat,
            config: config,
            phase: .readyForHand,
            completedHands: 0,
            stacks: stacks,
            checkpoint: nil,
            pendingHand: nil,
            activeHandID: nil,
            activeHandStartedAt: nil
        )
    }

    package var view: CashSessionView {
        let observation = restoredGame()?.spectatorObservation()
        let seats: [CashSeatView]
        if let observation {
            seats = observation.publicSeats.map {
                CashSeatView(
                    id: $0.id,
                    stack: $0.stack,
                    hasFolded: $0.hasFolded,
                    isAllIn: $0.isAllIn
                )
            }
        } else {
            seats = stacks.keys.sorted().map { seat in
                let stack = stacks[seat]!
                return CashSeatView(
                    id: seat,
                    stack: stack,
                    hasFolded: false,
                    isAllIn: stack.rawValue == 0
                )
            }
        }

        return CashSessionView(
            id: id,
            table: table,
            humanSeat: humanSeat,
            phase: phase,
            dealer: config.dealer,
            completedHands: completedHands,
            seats: seats,
            currentActor: observation?.currentActor
        )
    }

    @discardableResult
    package mutating func startHand(
        id: HandID,
        seed: UInt64,
        startedAt: Date
    ) throws -> GameTransition {
        try requireReady()
        try Self.validateTable(stacks: stacks, humanSeat: humanSeat)
        guard stacks[config.dealer] != nil else {
            throw PokerSessionError.invalidTable
        }

        let game = try HoldemGame.start(config: config, stacks: stacks, seed: seed)
        let newCheckpoint = game.makeCheckpoint()
        let transition = game.lastTransition

        checkpoint = newCheckpoint
        activeHandID = id
        activeHandStartedAt = startedAt
        phase = .handInProgress
        return transition
    }

    @discardableResult
    package mutating func apply(
        _ action: PlayerAction,
        by seat: SeatID
    ) throws -> GameTransition {
        guard phase == .handInProgress else {
            throw lifecycleError
        }
        let game = try requireRestoredGame()
        let transition = try game.apply(action, by: seat)
        try replaceState(after: game)
        return transition
    }

    @discardableResult
    package mutating func advanceIfRoundComplete() throws -> GameTransition {
        guard phase == .handInProgress else {
            throw lifecycleError
        }
        let game = try requireRestoredGame()
        let transition = try game.advanceIfRoundComplete()
        try replaceState(after: game)
        return transition
    }

    package func spectatorObservation() -> SpectatorObservation? {
        restoredGame()?.spectatorObservation()
    }

    package func playerObservation(for seat: SeatID) throws -> PlayerObservation? {
        guard let game = restoredGame() else { return nil }
        return try game.playerObservation(for: seat)
    }

    package mutating func markHandCommitted(_ id: HandID) throws {
        guard phase == .settlementPending else {
            throw PokerSessionError.handNotComplete
        }
        guard let pendingHand, pendingHand.id == id else {
            throw PokerSessionError.handNotComplete
        }

        let nextDealer = try SeatID((config.dealer.rawValue + 1) % 9)
        let nextConfig = try HandConfig(
            smallBlind: config.smallBlind,
            bigBlind: config.bigBlind,
            dealer: nextDealer
        )
        let (newCompletedHands, overflow) = completedHands.addingReportingOverflow(1)
        guard !overflow else { throw PokerSessionError.chipArithmeticOverflow }

        stacks = pendingHand.record.finalStacks
        config = nextConfig
        completedHands = newCompletedHands
        checkpoint = nil
        self.pendingHand = nil
        activeHandID = nil
        activeHandStartedAt = nil
        phase = .readyForHand
    }

    package mutating func addChips(_ amount: Chips, to seat: SeatID) throws {
        try requireReady()
        guard amount.rawValue > 0 else {
            throw PokerSessionError.invalidBuyIn
        }
        guard let current = stacks[seat] else {
            throw PokerSessionError.invalidTable
        }
        let (newRawValue, overflow) = current.rawValue.addingReportingOverflow(amount.rawValue)
        guard !overflow, let newStack = Chips(rawValue: newRawValue) else {
            throw PokerSessionError.chipArithmeticOverflow
        }
        if seat == humanSeat {
            try Self.validateHumanBuyIn(newStack, bigBlind: config.bigBlind)
        }
        stacks[seat] = newStack
    }

    @discardableResult
    package mutating func leave() throws -> Chips {
        try requireReady()
        guard let humanStack = stacks[humanSeat] else {
            throw PokerSessionError.invalidTable
        }
        phase = .left
        return humanStack
    }

    private var lifecycleError: PokerSessionError {
        phase == .settlementPending ? .settlementPending : .invalidLifecycle
    }

    private func requireReady() throws {
        guard phase == .readyForHand else { throw lifecycleError }
    }

    private func restoredGame() -> HoldemGame? {
        guard let checkpoint else { return nil }
        return try? HoldemGame.restore(from: checkpoint)
    }

    private func requireRestoredGame() throws -> HoldemGame {
        guard let checkpoint else { throw PokerSessionError.corruptSnapshot }
        do {
            return try HoldemGame.restore(from: checkpoint)
        } catch {
            throw PokerSessionError.corruptSnapshot
        }
    }

    private mutating func replaceState(after game: HoldemGame) throws {
        let newCheckpoint = game.makeCheckpoint()
        let observation = game.spectatorObservation()
        if observation.street == .complete {
            guard let activeHandID, let activeHandStartedAt else {
                throw PokerSessionError.corruptSnapshot
            }
            let record = try game.completedRecord()
            checkpoint = newCheckpoint
            pendingHand = PendingCashHand(
                id: activeHandID,
                startedAt: activeHandStartedAt,
                record: record
            )
            phase = .settlementPending
        } else {
            checkpoint = newCheckpoint
        }
    }

    private static func validateTable(
        stacks: [SeatID: Chips],
        humanSeat: SeatID
    ) throws {
        guard stacks.count == 9,
              stacks[humanSeat] != nil,
              stacks.values.allSatisfy({ $0.rawValue > 0 })
        else {
            throw PokerSessionError.invalidTable
        }
    }

    private static func validateHumanBuyIn(
        _ stack: Chips,
        bigBlind: Chips
    ) throws {
        let (minimum, minimumOverflow) = bigBlind.rawValue.multipliedReportingOverflow(
            by: SessionEconomy.minimumBuyInBigBlinds
        )
        let (maximum, maximumOverflow) = bigBlind.rawValue.multipliedReportingOverflow(
            by: SessionEconomy.maximumBuyInBigBlinds
        )
        guard !minimumOverflow, !maximumOverflow else {
            throw PokerSessionError.chipArithmeticOverflow
        }
        guard (minimum...maximum).contains(stack.rawValue) else {
            throw PokerSessionError.invalidBuyIn
        }
    }

    private func validateRestoredState() throws {
        guard stacks.count == 9,
              stacks[humanSeat] != nil,
              stacks[config.dealer] != nil,
              completedHands >= 0
        else {
            throw PokerSessionError.corruptSnapshot
        }

        switch phase {
        case .readyForHand, .left:
            guard checkpoint == nil,
                  pendingHand == nil,
                  activeHandID == nil,
                  activeHandStartedAt == nil
            else {
                throw PokerSessionError.corruptSnapshot
            }
        case .handInProgress:
            guard pendingHand == nil,
                  activeHandID != nil,
                  activeHandStartedAt != nil,
                  let checkpoint
            else {
                throw PokerSessionError.corruptSnapshot
            }
            let game = try HoldemGame.restore(from: checkpoint)
            guard game.spectatorObservation().street != .complete else {
                throw PokerSessionError.corruptSnapshot
            }
        case .settlementPending:
            guard let pendingHand,
                  pendingHand.id == activeHandID,
                  pendingHand.startedAt == activeHandStartedAt,
                  let checkpoint
            else {
                throw PokerSessionError.corruptSnapshot
            }
            let game = try HoldemGame.restore(from: checkpoint)
            guard game.spectatorObservation().street == .complete,
                  try game.completedRecord() == pendingHand.record
            else {
                throw PokerSessionError.corruptSnapshot
            }
        }
    }
}
