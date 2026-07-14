import Foundation

public enum BotError: Error, Equatable, Sendable {
    case invalidSettings
    case invalidObservation
}

public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case standard
    case hard
}

public enum BotModel: String, Codable, CaseIterable, Sendable {
    case conservative
    case balanced
    case aggressive
    case adaptive
}

public enum BotThinkingSpeed: String, Codable, CaseIterable, Sendable {
    case fast
    case standard
    case natural

    public var hardSimulationIterations: Int {
        switch self {
        case .fast: 800
        case .standard: 2_000
        case .natural: 5_000
        }
    }
}

public struct BotSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public static let recommended = try! BotSettings(
        difficulty: .standard,
        model: .balanced,
        aggression: 50,
        bluffFrequency: 30,
        callingWidth: 50,
        betSizing: 50,
        thinkingSpeed: .standard,
        analyzesHistory: true
    )

    public let schemaVersion: Int
    public let difficulty: BotDifficulty
    public let model: BotModel
    public let aggression: Int
    public let bluffFrequency: Int
    public let callingWidth: Int
    public let betSizing: Int
    public let thinkingSpeed: BotThinkingSpeed
    public let analyzesHistory: Bool

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        difficulty: BotDifficulty,
        model: BotModel,
        aggression: Int,
        bluffFrequency: Int,
        callingWidth: Int,
        betSizing: Int,
        thinkingSpeed: BotThinkingSpeed,
        analyzesHistory: Bool
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              [aggression, bluffFrequency, callingWidth, betSizing]
                .allSatisfy({ (0...100).contains($0) })
        else {
            throw BotError.invalidSettings
        }

        self.schemaVersion = schemaVersion
        self.difficulty = difficulty
        self.model = model
        self.aggression = aggression
        self.bluffFrequency = bluffFrequency
        self.callingWidth = callingWidth
        self.betSizing = betSizing
        self.thinkingSpeed = thinkingSpeed
        self.analyzesHistory = analyzesHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
                difficulty: container.decode(BotDifficulty.self, forKey: .difficulty),
                model: container.decode(BotModel.self, forKey: .model),
                aggression: container.decode(Int.self, forKey: .aggression),
                bluffFrequency: container.decode(Int.self, forKey: .bluffFrequency),
                callingWidth: container.decode(Int.self, forKey: .callingWidth),
                betSizing: container.decode(Int.self, forKey: .betSizing),
                thinkingSpeed: container.decode(BotThinkingSpeed.self, forKey: .thinkingSpeed),
                analyzesHistory: container.decode(Bool.self, forKey: .analyzesHistory)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "机器人设置无效",
                    underlyingError: error
                )
            )
        }
    }
}
