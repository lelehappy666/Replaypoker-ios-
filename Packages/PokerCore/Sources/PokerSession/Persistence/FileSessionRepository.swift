import Foundation

package enum AtomicWriteStage: CaseIterable, Sendable {
    case afterTemporaryWrite
    case afterSynchronize
    case beforeReplace
}

package protocol AtomicFileWriting {
    func write(_ data: Data, atomicallyTo destinationURL: URL) throws
}

package struct AtomicFileWriter: AtomicFileWriting {
    private let fileManager: FileManager
    private let stageHook: (AtomicWriteStage) throws -> Void

    package init(
        fileManager: FileManager = .default,
        stageHook: @escaping (AtomicWriteStage) throws -> Void = { _ in }
    ) {
        self.fileManager = fileManager
        self.stageHook = stageHook
    }

    package func write(_ data: Data, atomicallyTo destinationURL: URL) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")

        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw AtomicFileError.couldNotCreateTemporaryFile
        }

        var handle: FileHandle?
        defer {
            try? handle?.close()
            try? fileManager.removeItem(at: temporaryURL)
        }

        let openedHandle = try FileHandle(forWritingTo: temporaryURL)
        handle = openedHandle
        try openedHandle.write(contentsOf: data)
        try stageHook(.afterTemporaryWrite)
        try openedHandle.synchronize()
        try stageHook(.afterSynchronize)
        try openedHandle.close()
        handle = nil
        try stageHook(.beforeReplace)

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

    private enum AtomicFileError: Error {
        case couldNotCreateTemporaryFile
    }
}

package struct FileSessionRepository: SessionRepository {
    package let fileURL: URL
    private let writer: any AtomicFileWriting

    package init(
        directory: URL,
        writer: any AtomicFileWriting = AtomicFileWriter()
    ) {
        fileURL = directory.appendingPathComponent("river-club-state-v1.json")
        self.writer = writer
    }

    package func load() throws -> PersistedAppState {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if Self.isMissingFile(error) {
                return PersistedAppState()
            }
            throw PokerSessionError.persistenceFailed
        }

        do {
            return try JSONDecoder().decode(PersistedAppState.self, from: data)
        } catch let error as PokerSessionError {
            if case .unsupportedVersion = error {
                throw error
            }
            throw PokerSessionError.corruptSnapshot
        } catch {
            throw PokerSessionError.corruptSnapshot
        }
    }

    package func save(_ state: PersistedAppState) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try writer.write(encoder.encode(state), atomicallyTo: fileURL)
        } catch {
            throw PokerSessionError.persistenceFailed
        }
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError
    }
}
