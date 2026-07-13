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
}
