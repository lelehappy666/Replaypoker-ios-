import Foundation

struct PokerTableSummary: Identifiable, Equatable, Sendable {
    let id: UUID; let name: String; let smallBlind: Int; let bigBlind: Int
    let players: Int; let capacity: Int; let averagePot: Int; let isFavorite: Bool

    var hasOpenSeat: Bool { players < capacity }
}

enum LobbyCategory: String, CaseIterable, Identifiable, Sendable {
    case recommended = "为你推荐"
    case regular = "常规牌桌"
    case favorites = "已收藏"
    case beginner = "新手专区"

    var id: Self { self }

    func includes(_ table: PokerTableSummary) -> Bool {
        switch self {
        case .recommended, .regular:
            true
        case .favorites:
            table.isFavorite
        case .beginner:
            table.bigBlind <= 200
        }
    }
}

enum CommonBlindLevel: String, CaseIterable, Identifiable, Sendable {
    case oneHundredTwoHundred = "100 / 200"
    case twoHundredFourHundred = "200 / 400"
    case fiveHundredOneThousand = "500 / 1,000"

    var id: Self { self }

    var blinds: (small: Int, big: Int) {
        switch self {
        case .oneHundredTwoHundred: (100, 200)
        case .twoHundredFourHundred: (200, 400)
        case .fiveHundredOneThousand: (500, 1_000)
        }
    }
}

enum QuickJoinMatcher {
    static func match(
        in tables: [PokerTableSummary],
        blind: CommonBlindLevel
    ) -> PokerTableSummary? {
        let selected = blind.blinds
        return tables.first {
            $0.smallBlind == selected.small
                && $0.bigBlind == selected.big
                && $0.hasOpenSeat
        }
    }
}

enum TablePrimaryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case low = "低盲注"
    case medium = "中盲注"
    case high = "高盲注"
    case favorites = "收藏"

    var id: Self { self }

    func includes(_ table: PokerTableSummary) -> Bool {
        switch self {
        case .all: true
        case .low: table.bigBlind <= 200
        case .medium: table.bigBlind > 200 && table.bigBlind < 1_000
        case .high: table.bigBlind >= 1_000
        case .favorites: table.isFavorite
        }
    }
}

enum TableTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case nineSeat = "九人桌"

    var id: Self { self }

    func includes(_ table: PokerTableSummary) -> Bool {
        table.capacity == 9
    }
}

enum SeatAvailabilityFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "不限空位"
    case openSeats = "仅看空位"

    var id: Self { self }

    func includes(_ table: PokerTableSummary) -> Bool {
        self == .all || table.hasOpenSeat
    }
}

enum BlindRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部盲注"
    case low = "1–200"
    case medium = "201–999"
    case high = "1,000+"

    var id: Self { self }

    func includes(_ table: PokerTableSummary) -> Bool {
        switch self {
        case .all: true
        case .low: table.bigBlind <= 200
        case .medium: table.bigBlind > 200 && table.bigBlind < 1_000
        case .high: table.bigBlind >= 1_000
        }
    }
}

struct TableListFilters: Equatable, Sendable {
    var primary: TablePrimaryFilter = .all
    var tableType: TableTypeFilter = .nineSeat
    var seatAvailability: SeatAvailabilityFilter = .all
    var blindRange: BlindRangeFilter = .all

    func apply(to tables: [PokerTableSummary]) -> [PokerTableSummary] {
        tables.filter {
            primary.includes($0)
                && tableType.includes($0)
                && seatAvailability.includes($0)
                && blindRange.includes($0)
        }
    }
}

enum JoinDisposition: Equatable, Sendable {
    case buyIn
    case waitlist

    init(table: PokerTableSummary) {
        self = table.hasOpenSeat ? .buyIn : .waitlist
    }
}

struct PokerSeat: Identifiable, Equatable, Sendable {
    let id: UUID; let position: Int; let initials: String; let name: String
    let chips: Int; let isLocalPlayer: Bool; let status: String?
}

struct TournamentSummary: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case beginner, classic, turbo }
    let id: UUID; let kind: Kind; let name: String; let startTime: Date
    let registered: Int; let capacity: Int; let prizePool: Int; let entryChips: Int
}

struct ProfileSummary: Equatable, Sendable {
    let nickname: String; let level: Int; let handsPlayed: Int
    let voluntaryPutInPot: Double; let tournamentAwards: Int
}
