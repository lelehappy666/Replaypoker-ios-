import Foundation
import PokerCore
import PokerSession

func makeHistoryRecord(
    foldedSeat: SeatID? = SeatID(rawValue: 3)!,
    humanSeat: SeatID = SeatID(rawValue: 0)!,
    archiveMetadata: HandArchiveMetadata?
) throws -> StoredHandRecord {
    let seats = (0..<9).map { SeatID(rawValue: $0)! }
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: SeatID(rawValue: 6)!
        ),
        stacks: Dictionary(uniqueKeysWithValues: seats.map { ($0, Chips(rawValue: 4_000)!) }),
        seed: 7
    )

    while let actor = game.spectatorObservation().currentActor {
        try game.apply(.fold, by: actor)
    }
    try game.advanceIfRoundComplete()
    let completed = try game.completedRecord()
    if let foldedSeat {
        guard completed.actions.contains(where: {
            $0.seat == foldedSeat && $0.action == .fold
        }) else {
            throw PokerRuleError.invalidState("requested fixture seat did not fold")
        }
    }

    return StoredHandRecord(
        id: try HandID("history-fold-hand-\(foldedSeat?.rawValue ?? -1)-\(humanSeat.rawValue)"),
        sessionID: try SessionID("history-session"),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 1_000),
        endedAt: Date(timeIntervalSince1970: 1_060),
        localDay: try LocalDay("2026-07-14"),
        handNumber: 42,
        record: completed,
        archiveMetadata: archiveMetadata
    )
}

func makeMultiPotHistoryRecord() throws -> StoredHandRecord {
    let seat0 = SeatID(rawValue: 0)!
    let seat1 = SeatID(rawValue: 1)!
    let seat2 = SeatID(rawValue: 2)!
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(1),
            bigBlind: try Chips(2),
            dealer: seat0
        ),
        stacks: [
            seat0: try Chips(101),
            seat1: try Chips(301),
            seat2: try Chips(500),
        ],
        seed: 22
    )

    try game.apply(.allIn, by: seat0)
    try game.apply(.allIn, by: seat1)
    try game.apply(.call, by: seat2)
    try game.advanceIfRoundComplete()

    return StoredHandRecord(
        id: try HandID("history-multi-pot-hand"),
        sessionID: try SessionID("history-session"),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 2_000),
        endedAt: Date(timeIntervalSince1970: 2_060),
        localDay: try LocalDay("2026-07-15"),
        handNumber: 43,
        record: try game.completedRecord(),
        archiveMetadata: try makePresentationArchiveMetadata()
    )
}

func makeUncalledReturnHistoryRecord() throws -> StoredHandRecord {
    let seat0 = SeatID(rawValue: 0)!
    let seat1 = SeatID(rawValue: 1)!
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [
            seat0: try Chips(1_000),
            seat1: try Chips(30),
        ],
        seed: 20
    )
    try game.apply(.fold, by: seat0)
    try game.advanceIfRoundComplete()
    let completed = try game.completedRecord()
    guard !completed.uncalledReturns.isEmpty else {
        throw PokerRuleError.invalidState("uncalled return fixture is empty")
    }

    return StoredHandRecord(
        id: try HandID("history-uncalled-return"),
        sessionID: try SessionID("history-session"),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 3_000),
        endedAt: Date(timeIntervalSince1970: 3_060),
        localDay: try LocalDay("2026-07-16"),
        handNumber: 44,
        record: completed,
        archiveMetadata: try makePresentationArchiveMetadata()
    )
}

func makePresentationArchiveMetadata() throws -> HandArchiveMetadata {
    try HandArchiveMetadata(
        tableDisplayName: "翡翠湾高额桌",
        humanSeat: SeatID(rawValue: 0)!,
        seatDisplayNames: Dictionary(uniqueKeysWithValues: (0..<9).map {
            (SeatID(rawValue: $0)!, "玩家\($0 + 1)")
        })
    )
}
