import Foundation

struct MockPokerRepository: PokerRepository {
    func tables() async throws -> [PokerTableSummary] {
        Self.tableFixtures
    }

    func featuredTable() async throws -> PokerTableSummary {
        Self.tableFixtures[0]
    }

    func seats() async throws -> [PokerSeat] {
        Self.seatFixtures
    }

    func tournaments() async throws -> [TournamentSummary] {
        Self.tournamentFixtures
    }

    func profile() async throws -> ProfileSummary {
        ProfileSummary(
            nickname: "RiverAce",
            level: 18,
            handsPlayed: 2_486,
            voluntaryPutInPot: 24.6,
            tournamentAwards: 12
        )
    }

    private static let tableFixtures = [
        PokerTableSummary(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "翡翠湾",
            smallBlind: 100,
            bigBlind: 200,
            players: 7,
            capacity: 9,
            averagePot: 3_800,
            isFavorite: true
        ),
        PokerTableSummary(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "金色海岸",
            smallBlind: 200,
            bigBlind: 400,
            players: 8,
            capacity: 9,
            averagePot: 7_200,
            isFavorite: false
        ),
        PokerTableSummary(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "午夜俱乐部",
            smallBlind: 500,
            bigBlind: 1_000,
            players: 6,
            capacity: 9,
            averagePot: 18_500,
            isFavorite: true
        ),
    ]

    private static let seatFixtures = [
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            position: 1,
            initials: "LM",
            name: "林墨",
            chips: 24_800,
            isLocalPlayer: false,
            status: "庄家"
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            position: 2,
            initials: "QY",
            name: "青屿",
            chips: 18_600,
            isLocalPlayer: false,
            status: "小盲"
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
            position: 3,
            initials: "RA",
            name: "RiverAce",
            chips: 32_400,
            isLocalPlayer: true,
            status: "大盲"
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            position: 4,
            initials: "KS",
            name: "空山",
            chips: 21_900,
            isLocalPlayer: false,
            status: nil
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000005")!,
            position: 5,
            initials: "YN",
            name: "云雀",
            chips: 27_300,
            isLocalPlayer: false,
            status: nil
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000006")!,
            position: 6,
            initials: "CX",
            name: "晨星",
            chips: 15_700,
            isLocalPlayer: false,
            status: nil
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000007")!,
            position: 7,
            initials: "HY",
            name: "海盐",
            chips: 19_200,
            isLocalPlayer: false,
            status: nil
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000008")!,
            position: 8,
            initials: "JW",
            name: "玖未",
            chips: 30_100,
            isLocalPlayer: false,
            status: nil
        ),
        PokerSeat(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000009")!,
            position: 9,
            initials: "SY",
            name: "深野",
            chips: 22_500,
            isLocalPlayer: false,
            status: nil
        ),
    ]

    private static let tournamentFixtures = [
        TournamentSummary(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            kind: .beginner,
            name: "新星启航赛",
            startTime: Date(timeIntervalSince1970: 1_800_000_000),
            registered: 36,
            capacity: 64,
            prizePool: 120_000,
            entryChips: 2_000
        ),
        TournamentSummary(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            kind: .classic,
            name: "河畔经典赛",
            startTime: Date(timeIntervalSince1970: 1_800_003_600),
            registered: 78,
            capacity: 120,
            prizePool: 500_000,
            entryChips: 8_000
        ),
        TournamentSummary(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            kind: .turbo,
            name: "极速深夜赛",
            startTime: Date(timeIntervalSince1970: 1_800_007_200),
            registered: 42,
            capacity: 54,
            prizePool: 240_000,
            entryChips: 5_000
        ),
    ]
}
