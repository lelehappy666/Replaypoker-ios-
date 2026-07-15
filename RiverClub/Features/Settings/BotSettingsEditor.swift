import Observation
import PokerBot

@MainActor @Observable
final class BotSettingsEditor {
    var draft: BotSettings
    private(set) var saved: BotSettings
    private(set) var isRestoreConfirmationPresented = false

    init(current: BotSettings) {
        draft = current
        saved = current
    }

    var hasUnsavedChanges: Bool { draft != saved }

    func confirmSave(in session: AppSession) throws {
        try session.saveBotSettings(draft)
        saved = draft
    }

    func requestRestoreRecommended() {
        isRestoreConfirmationPresented = true
    }

    func cancelRestoreRecommended() {
        isRestoreConfirmationPresented = false
    }

    func confirmRestoreRecommended(in session: AppSession) throws {
        guard isRestoreConfirmationPresented else { return }
        try session.restoreRecommendedBotSettings(confirmed: true)
        draft = session.botSettings
        saved = session.botSettings
        isRestoreConfirmationPresented = false
    }
}
