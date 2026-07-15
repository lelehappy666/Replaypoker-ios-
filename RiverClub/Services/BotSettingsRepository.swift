import Foundation
import PokerBot

enum BotSettingsRepositoryError: Error, Equatable {
    case corruptSettings
    case persistenceFailed
}

protocol BotSettingsPersisting: AnyObject {
    func load() throws -> BotSettings
    func save(_ settings: BotSettings) throws
    @discardableResult func restoreRecommended() throws -> BotSettings
}

extension BotSettingsPersisting {
    @discardableResult
    func restoreRecommended() throws -> BotSettings {
        try save(.recommended)
        return .recommended
    }
}

protocol BotSettingsFileWriting: Sendable {
    func write(_ data: Data, atomicallyTo destinationURL: URL) throws
}

struct AtomicBotSettingsFileWriter: BotSettingsFileWriting {
    func write(_ data: Data, atomicallyTo destinationURL: URL) throws {
        let fileManager = FileManager.default
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw BotSettingsRepositoryError.persistenceFailed
        }

        var handle: FileHandle?
        defer {
            try? handle?.close()
            try? fileManager.removeItem(at: temporaryURL)
        }
        let opened = try FileHandle(forWritingTo: temporaryURL)
        handle = opened
        try opened.write(contentsOf: data)
        try opened.synchronize()
        try opened.close()
        handle = nil

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}

final class BotSettingsRepository: BotSettingsPersisting {
    let fileURL: URL
    private let writer: any BotSettingsFileWriting

    init(
        directory: URL,
        writer: any BotSettingsFileWriting = AtomicBotSettingsFileWriter()
    ) {
        fileURL = directory.appendingPathComponent("bot-settings-v1.json")
        self.writer = writer
    }

    static func applicationSupport(
        fileManager: FileManager = .default
    ) throws -> BotSettingsRepository {
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BotSettingsRepositoryError.persistenceFailed
        }
        let directory = root.appendingPathComponent("RiverClub", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return BotSettingsRepository(directory: directory)
        } catch {
            throw BotSettingsRepositoryError.persistenceFailed
        }
    }

    func load() throws -> BotSettings {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == NSFileReadNoSuchFileError {
                return .recommended
            }
            throw BotSettingsRepositoryError.persistenceFailed
        }
        do {
            return try JSONDecoder().decode(BotSettings.self, from: data)
        } catch {
            throw BotSettingsRepositoryError.corruptSettings
        }
    }

    func save(_ settings: BotSettings) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try writer.write(encoder.encode(settings), atomicallyTo: fileURL)
        } catch {
            throw BotSettingsRepositoryError.persistenceFailed
        }
    }
}

final class MemoryBotSettingsRepository: BotSettingsPersisting {
    private var settings: BotSettings

    init(initial: BotSettings) {
        settings = initial
    }

    func load() throws -> BotSettings { settings }
    func save(_ settings: BotSettings) throws { self.settings = settings }
}
