import Foundation
import PokerCore

public enum PokerSessionError: Error, Equatable, Sendable {
    case invalidIdentifier
    case chipArithmeticOverflow
    case insufficientBalance
    case businessIDConflict
    case dailyGiftAlreadyClaimed
    case reliefNotAvailable
    case invalidBuyIn
    case invalidTable
    case invalidLifecycle
    case handNotComplete
    case settlementPending
    case unsupportedVersion(Int)
    case corruptSnapshot
    case persistenceFailed
    case recordNotFound
}

public protocol SessionIdentifier: Codable, Hashable, Sendable {
    var rawValue: String { get }
    init(_ rawValue: String) throws
}

public extension SessionIdentifier {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self = try Self(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid session identifier"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BusinessID: SessionIdentifier {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct SessionID: SessionIdentifier {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct HandID: SessionIdentifier {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct TableID: SessionIdentifier {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct LocalDay: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            throw PokerSessionError.invalidIdentifier
        }

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            throw PokerSessionError.invalidIdentifier
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year,
              components.month == month,
              components.day == day
        else {
            throw PokerSessionError.invalidIdentifier
        }

        self.rawValue = rawValue
    }

    public init?(rawValue: String) {
        guard let value = try? Self(rawValue) else { return nil }
        self = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self = try Self(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid local day"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public protocol SessionClock: Sendable {
    var now: Date { get }
    var currentDay: LocalDay { get }
}

public struct FixedSessionClock: SessionClock {
    public let now: Date
    public let currentDay: LocalDay

    public init(now: Date, day: LocalDay) {
        self.now = now
        currentDay = day
    }
}

public enum SessionEconomy {
    public static let initialBalance = Chips(rawValue: 128_500)!
    public static let dailyGift = Chips(rawValue: 10_000)!
    public static let reliefThreshold = Chips(rawValue: 2_000)!
    public static let reliefTarget = Chips(rawValue: 20_000)!
    public static let minimumBuyInBigBlinds = 40
    public static let maximumBuyInBigBlinds = 100
}
