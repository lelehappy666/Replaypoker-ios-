import Foundation
import XCTest
@testable import RiverClub

final class MockPokerRepositoryTests: XCTestCase {
    private let repository = MockPokerRepository()

    func testTablesProvideApprovedDeterministicFixtures() async throws {
        let tables = try await repository.tables()

        XCTAssertGreaterThanOrEqual(tables.count, 3)
        XCTAssertEqual(tables.map(\.name), ["翡翠湾", "金色海岸", "午夜俱乐部"])
        XCTAssertEqual(
            tables.map(\.id),
            (1...3).compactMap {
                UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", $0))
            }
        )
    }

    func testFeaturedTableHasAnOpenSeat() async throws {
        let table = try await repository.featuredTable()

        XCTAssertLessThan(table.players, table.capacity)
    }

    func testSeatsHaveNineUniquePositionsAndOneLocalPlayer() async throws {
        let seats = try await repository.seats()

        XCTAssertEqual(seats.count, 9)
        XCTAssertEqual(Set(seats.map(\.position)).count, 9)
        XCTAssertEqual(seats.filter(\.isLocalPlayer).count, 1)
        XCTAssertEqual(
            seats.map(\.id),
            (1...9).compactMap {
                UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", $0))
            }
        )
    }

    func testFormattedFixtureValuesDoNotUseRealCurrencySymbols() async throws {
        let tables = try await repository.tables()
        let seats = try await repository.seats()
        let tournaments = try await repository.tournaments()
        let profile = try await repository.profile()
        var values = tables.flatMap {
            [$0.name, String($0.smallBlind), String($0.bigBlind), String($0.averagePot)]
        }
        values += seats.flatMap {
            [$0.initials, $0.name, String($0.chips), $0.status ?? ""]
        }
        values += tournaments.flatMap {
            [$0.kind.rawValue, $0.name, String($0.prizePool), String($0.entryChips)]
        }
        values += [
            profile.nickname,
            String(profile.handsPlayed),
            String(profile.voluntaryPutInPot),
            String(profile.tournamentAwards),
        ]

        for symbol in ["¥", "$", "€", "£"] {
            XCTAssertFalse(values.contains { $0.contains(symbol) })
        }
    }

    func testUpcomingTournamentsExcludePastStartTimes() {
        let now = Date(timeIntervalSince1970: 2_000)
        let past = tournament(id: 1, startTime: now.addingTimeInterval(-1))
        let future = tournament(id: 2, startTime: now.addingTimeInterval(1))

        XCTAssertEqual(
            TournamentTab.upcoming.filtered([past, future], now: now),
            [future]
        )
    }

    func testRegisteredTournamentsOnlyIncludeProvidedIdentifiers() {
        let first = tournament(id: 1, startTime: Date(timeIntervalSince1970: 2_001))
        let second = tournament(id: 2, startTime: Date(timeIntervalSince1970: 2_002))

        XCTAssertEqual(
            TournamentTab.registered.filtered(
                [first, second],
                now: Date(timeIntervalSince1970: 2_000),
                registeredIDs: [second.id]
            ),
            [second]
        )
    }

    func testActiveAndFinishedTournamentsUseExplicitEndTimeBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000)
        let active = tournament(
            id: 1,
            startTime: now.addingTimeInterval(-1),
            endTime: now.addingTimeInterval(1)
        )
        let startsNow = tournament(id: 2, startTime: now, endTime: now.addingTimeInterval(1))
        let endsNow = tournament(id: 3, startTime: now.addingTimeInterval(-1), endTime: now)

        XCTAssertEqual(TournamentTab.active.filtered([active, startsNow, endsNow], now: now), [active, startsNow])
        XCTAssertEqual(TournamentTab.finished.filtered([active, startsNow, endsNow], now: now), [endsNow])
    }

    func testProfileFixtureVPIPIsAUnitIntervalRatio() async throws {
        let profile = try await repository.profile()

        XCTAssertTrue((0...1).contains(profile.voluntaryPutInPot))
    }

    private func tournament(
        id: Int,
        startTime: Date,
        endTime: Date? = nil
    ) -> TournamentSummary {
        TournamentSummary(
            id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", id))!,
            kind: .classic,
            name: "测试赛事\(id)",
            startTime: startTime,
            endTime: endTime ?? startTime.addingTimeInterval(3_600),
            registered: 12,
            capacity: 64,
            prizePool: 100_000,
            entryChips: 2_000
        )
    }
}

final class TournamentPresentationTests: XCTestCase {
    func testPaidTournamentButtonUsesAvailableHighContrastStyle() {
        let presentation = TournamentRegistrationPresentation(
            entryChips: 8_000,
            isRegistered: false
        )

        XCTAssertEqual(presentation.title, "报名 · $8,000")
        XCTAssertEqual(presentation.style, .available)
        XCTAssertTrue(presentation.isEnabled)
    }

    func testFreeTournamentButtonKeepsAvailableHighContrastStyle() {
        let presentation = TournamentRegistrationPresentation(
            entryChips: 0,
            isRegistered: false
        )

        XCTAssertEqual(presentation.title, "免费报名")
        XCTAssertEqual(presentation.style, .available)
        XCTAssertTrue(presentation.isEnabled)
    }

    func testRegisteredTournamentButtonUsesDistinctDisabledStyle() {
        let presentation = TournamentRegistrationPresentation(
            entryChips: 0,
            isRegistered: true
        )

        XCTAssertEqual(presentation.title, "已报名")
        XCTAssertEqual(presentation.style, .registered)
        XCTAssertFalse(presentation.isEnabled)
    }
}
