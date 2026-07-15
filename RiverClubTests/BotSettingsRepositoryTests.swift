import Foundation
import PokerBot
import XCTest
@testable import RiverClub

final class BotSettingsRepositoryTests: XCTestCase {
    func test首次打开返回推荐设置且不主动创建文件() throws {
        let directory = try SettingsTemporaryDirectory()
        let repository = BotSettingsRepository(directory: directory.url)

        XCTAssertEqual(try repository.load(), .recommended)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func test保存后重开恢复完全相同设置() throws {
        let directory = try SettingsTemporaryDirectory()
        let repository = BotSettingsRepository(directory: directory.url)
        let custom = try makeBotSettings(aggression: 83, model: .aggressive)

        try repository.save(custom)

        XCTAssertEqual(try BotSettingsRepository(directory: directory.url).load(), custom)
    }

    func test损坏文件明确报错且不会被推荐设置覆盖() throws {
        let directory = try SettingsTemporaryDirectory()
        let repository = BotSettingsRepository(directory: directory.url)
        let damaged = Data("不是合法设置".utf8)
        try damaged.write(to: repository.fileURL)

        XCTAssertThrowsError(try repository.load()) { error in
            XCTAssertEqual(error as? BotSettingsRepositoryError, .corruptSettings)
        }
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func test损坏文件只有显式恢复后才会写入推荐设置() throws {
        let directory = try SettingsTemporaryDirectory()
        let repository = BotSettingsRepository(directory: directory.url)
        try Data("损坏".utf8).write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())

        XCTAssertEqual(try repository.restoreRecommended(), .recommended)
        XCTAssertEqual(try repository.load(), .recommended)
    }

    func test失败写入保留旧设置() throws {
        let directory = try SettingsTemporaryDirectory()
        let initial = BotSettingsRepository(directory: directory.url)
        let old = try makeBotSettings(aggression: 20)
        try initial.save(old)
        let failing = BotSettingsRepository(
            directory: directory.url,
            writer: FailingBotSettingsWriter()
        )

        XCTAssertThrowsError(try failing.save(try makeBotSettings(aggression: 90)))
        XCTAssertEqual(try initial.load(), old)
    }

    @MainActor
    func test编辑器确认保存并要求显式确认后恢复推荐设置() throws {
        let repository = MemoryBotSettingsRepository(initial: .recommended)
        let session = try AppSessionFixture(
            botSettingsRepository: repository
        ).session
        let editor = BotSettingsEditor(current: session.botSettings)
        let custom = try makeBotSettings(aggression: 88)
        editor.draft = custom

        try editor.confirmSave(in: session)
        XCTAssertEqual(session.botSettings, custom)
        XCTAssertEqual(try repository.load(), custom)

        editor.requestRestoreRecommended()
        editor.cancelRestoreRecommended()
        XCTAssertEqual(editor.draft, custom)
        editor.requestRestoreRecommended()
        try editor.confirmRestoreRecommended(in: session)
        XCTAssertEqual(session.botSettings, .recommended)
        XCTAssertEqual(editor.draft, .recommended)
    }

    @MainActor
    func test每手冻结快照不受本手中设置修改影响() throws {
        let repository = MemoryBotSettingsRepository(initial: .recommended)
        let session = try AppSessionFixture(
            botSettingsRepository: repository
        ).session
        let frozen = session.freezeBotSettingsForNextHand()

        try session.saveBotSettings(try makeBotSettings(aggression: 100))

        XCTAssertEqual(frozen, .recommended)
        XCTAssertEqual(session.frozenBotSettings, .recommended)
        XCTAssertEqual(session.freezeBotSettingsForNextHand().aggression, 100)
    }
}

private func makeBotSettings(
    aggression: Int,
    model: BotModel = .balanced
) throws -> BotSettings {
    try BotSettings(
        difficulty: .standard,
        model: model,
        aggression: aggression,
        bluffFrequency: 30,
        callingWidth: 50,
        betSizing: 50,
        thinkingSpeed: .standard,
        analyzesHistory: true
    )
}

private struct FailingBotSettingsWriter: BotSettingsFileWriting {
    func write(_ data: Data, atomicallyTo destinationURL: URL) throws {
        throw BotSettingsRepositoryError.persistenceFailed
    }
}

private final class SettingsTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-bot-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
