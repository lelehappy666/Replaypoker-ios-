import Foundation

enum TableAnimationSpeed: String, Codable, CaseIterable, Equatable {
    case slow
    case standard
    case fast

    var durationMultiplier: Double {
        switch self {
        case .slow: 1.28
        case .standard: 1
        case .fast: 0.76
        }
    }
}

struct TableExperienceSettings: Codable, Equatable {
    var chipAnimationEnabled: Bool
    var speed: TableAnimationSpeed
    var currentHandHintEnabled: Bool
    var autoTopUpEnabled: Bool

    static let recommended = TableExperienceSettings(
        chipAnimationEnabled: true,
        speed: .standard,
        currentHandHintEnabled: true,
        autoTopUpEnabled: false
    )
}

enum TableExperiencePreference {
    static let chipAnimationEnabledKey = "riverClub.chipAnimationEnabled"
    static let animationSpeedKey = "riverClub.chipAnimationSpeed"
    static let currentHandHintEnabledKey = "riverClub.currentHandHintEnabled"
    static let autoTopUpEnabledKey = "riverClub.autoTopUpEnabled"
}

protocol TableExperienceSettingsPersisting: AnyObject {
    func load() throws -> TableExperienceSettings
    func save(_ settings: TableExperienceSettings) throws
}

final class TableExperienceSettingsRepository: TableExperienceSettingsPersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> TableExperienceSettings {
        let recommended = TableExperienceSettings.recommended
        let speed = defaults.string(
            forKey: TableExperiencePreference.animationSpeedKey
        ).flatMap(TableAnimationSpeed.init(rawValue:)) ?? recommended.speed
        return TableExperienceSettings(
            chipAnimationEnabled: defaults.object(
                forKey: TableExperiencePreference.chipAnimationEnabledKey
            ) as? Bool ?? recommended.chipAnimationEnabled,
            speed: speed,
            currentHandHintEnabled: defaults.object(
                forKey: TableExperiencePreference.currentHandHintEnabledKey
            ) as? Bool ?? recommended.currentHandHintEnabled,
            autoTopUpEnabled: defaults.object(
                forKey: TableExperiencePreference.autoTopUpEnabledKey
            ) as? Bool ?? recommended.autoTopUpEnabled
        )
    }

    func save(_ settings: TableExperienceSettings) throws {
        defaults.set(
            settings.chipAnimationEnabled,
            forKey: TableExperiencePreference.chipAnimationEnabledKey
        )
        defaults.set(
            settings.speed.rawValue,
            forKey: TableExperiencePreference.animationSpeedKey
        )
        defaults.set(
            settings.currentHandHintEnabled,
            forKey: TableExperiencePreference.currentHandHintEnabledKey
        )
        defaults.set(
            settings.autoTopUpEnabled,
            forKey: TableExperiencePreference.autoTopUpEnabledKey
        )
    }
}

final class MemoryTableExperienceSettingsRepository: TableExperienceSettingsPersisting {
    private var settings: TableExperienceSettings

    init(initial: TableExperienceSettings = .recommended) {
        settings = initial
    }

    func load() throws -> TableExperienceSettings { settings }
    func save(_ settings: TableExperienceSettings) throws { self.settings = settings }
}
