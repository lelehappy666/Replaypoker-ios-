import Foundation
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

func decodeLegalActions(_ json: String) throws -> LegalActionSet {
    try JSONDecoder().decode(LegalActionSet.self, from: Data(json.utf8))
}

func makeSafeTableViewState() throws -> TableViewState {
    let humanSeat = try SeatID(0)
    let botSeat = try SeatID(1)
    let aceOfSpades = try #require(
        Card.fullDeck.first { $0.rank == .ace && $0.suit == .spades }
    )
    let kingOfSpades = try #require(
        Card.fullDeck.first { $0.rank == .king && $0.suit == .spades }
    )
    let queenOfHearts = try #require(
        Card.fullDeck.first { $0.rank == .queen && $0.suit == .hearts }
    )
    return TableViewState(
        handID: "safe-hand",
        stateVersion: 1,
        phase: .waitingForHuman,
        seats: [
            TableSeatState(
                id: humanSeat,
                displayName: "玩家",
                stack: try Chips(3_800),
                committedThisStreet: try Chips(200),
                hasFolded: false,
                isAllIn: false,
                isDealer: true,
                isCurrentActor: true,
                cards: [
                    .faceUp(aceOfSpades),
                    .faceUp(kingOfSpades),
                ]
            ),
            TableSeatState(
                id: botSeat,
                displayName: "机器人",
                stack: try Chips(3_400),
                committedThisStreet: try Chips(600),
                hasFolded: false,
                isAllIn: false,
                isDealer: false,
                isCurrentActor: false,
                cards: [.faceDown, .faceDown]
            ),
        ],
        communityCards: [queenOfHearts],
        pot: try Chips(800),
        controls: nil,
        secondsRemaining: 12,
        winners: [],
        errorMessage: nil,
        animation: .dealHoleCard(seat: botSeat, card: .faceDown)
    )
}

final class CoordinatorStoreFixture {
    let store: LocalPokerStore
    let humanSeat: SeatID
    let seatProfiles: [TableSeatProfile]
    let bustedBot: SeatID
    let showdownSeat: SeatID
    let foldedSeat: SeatID
    let completedRecord: CompletedHandRecord

    private let directory: URL

    private init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        bustedBot: SeatID,
        showdownSeat: SeatID,
        foldedSeat: SeatID,
        completedRecord: CompletedHandRecord,
        directory: URL
    ) {
        self.store = store
        self.humanSeat = humanSeat
        self.seatProfiles = seatProfiles
        self.bustedBot = bustedBot
        self.showdownSeat = showdownSeat
        self.foldedSeat = foldedSeat
        self.completedRecord = completedRecord
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func finishedHandWithBustedBot() throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "finished-busted-bot")
        do {
            let lowStackBot = try SeatID(1)
            let store = try makeSeatedStore(
                directory: directory,
                botStackOverrides: [lowStackBot: try Chips(1)]
            )
            try playToShowdown(in: store, foldedSeat: nil, seed: 7)
            let record = try pendingRecord(in: directory)
            let humanSeat = try SeatID(0)
            let bustedBot = try #require(
                record.finalStacks.keys.sorted().first {
                    $0 != humanSeat && record.finalStacks[$0]?.rawValue == 0
                }
            )
            _ = try store.commitPendingHand(transactionID: try BusinessID("settle-busted-bot"))
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != bustedBot }
            )
            return CoordinatorStoreFixture(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                bustedBot: bustedBot,
                showdownSeat: showdownSeat,
                foldedSeat: try SeatID(3),
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func pendingShowdown() throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "pending-showdown")
        do {
            let foldedSeat = try SeatID(3)
            let store = try makeSeatedStore(directory: directory)
            try playToShowdown(in: store, foldedSeat: foldedSeat, seed: 11)
            let record = try pendingRecord(in: directory)
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != foldedSeat }
            )
            return CoordinatorStoreFixture(
                store: store,
                humanSeat: try SeatID(0),
                seatProfiles: try makeSeatProfiles(),
                bustedBot: try SeatID(1),
                showdownSeat: showdownSeat,
                foldedSeat: foldedSeat,
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func readyWithBustedBot() throws -> CoordinatorStoreFixture {
        try finishedHandWithBustedBot()
    }
}

private let coordinatorClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "river-club-coordinator-\(name)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func makeSeatedStore(
    directory: URL,
    botStackOverrides: [SeatID: Chips] = [:]
) throws -> LocalPokerStore {
    let humanSeat = try SeatID(0)
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map { rawSeat in
        let seat = try SeatID(rawSeat)
        let stack = try botStackOverrides[seat] ?? Chips(4_000)
        return (seat, stack)
    })
    let request = CashTableRequest(
        sessionID: try SessionID("coordinator-session"),
        table: try TableID("coordinator-table"),
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: humanSeat
        ),
        humanSeat: humanSeat,
        stacks: stacks
    )
    let store = try LocalPokerStore.open(directory: directory, clock: coordinatorClock)
    _ = try store.sitDown(
        request: request,
        businessID: try BusinessID("coordinator-buy-in")
    )
    return store
}

private func makeSeatProfiles() throws -> [TableSeatProfile] {
    try (0..<9).map { rawSeat in
        try TableSeatProfile(
            id: SeatID(rawSeat),
            displayName: rawSeat == 0 ? "玩家" : "机器人 \(rawSeat)"
        )
    }
}

private func playToShowdown(
    in store: LocalPokerStore,
    foldedSeat: SeatID?,
    seed: UInt64
) throws {
    _ = try store.startHand(id: try HandID("coordinator-hand"), seed: seed)
    var hasFoldedDesignatedSeat = false
    var remainingSteps = 200

    while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
        remainingSteps -= 1
        if let actor = store.cashSession?.currentActor {
            let observation = try #require(try store.playerObservation(for: actor))
            let legal = try #require(observation.legalActions)
            let action: PlayerAction
            if actor == foldedSeat, !hasFoldedDesignatedSeat, legal.canFold {
                action = .fold
                hasFoldedDesignatedSeat = true
            } else if legal.canCheck {
                action = .check
            } else if legal.callAmount != nil {
                action = .call
            } else {
                action = .fold
            }
            _ = try store.apply(action, by: actor)
        } else {
            _ = try store.advanceIfRoundComplete()
        }
    }

    #expect(remainingSteps > 0)
    #expect(store.cashSession?.phase == .settlementPending)
    if foldedSeat != nil {
        #expect(hasFoldedDesignatedSeat)
    }
}

private func pendingRecord(in directory: URL) throws -> CompletedHandRecord {
    try #require(
        FileSessionRepository(directory: directory)
            .load()
            .activeCashSession?
            .pendingHand?
            .record
    )
}
