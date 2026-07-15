import Foundation
import PokerCoordinator
import Testing

@Test func 普通导入无法访问牌桌与协调器隐藏信息() throws {
    for probe in HiddenInformationProbe.allCases {
        try expectTypecheckFailure(probe)
    }
}

private enum HiddenInformationProbe: String, CaseIterable {
    case deck = "_ = tableState.deck"
    case seed = "_ = tableState.seed"
    case checkpoint = "_ = tableState.checkpoint"
    case opponentHoleCards = "_ = tableState.opponentHoleCards"
    case arbitraryPlayerObservation =
        "_ = coordinator.playerObservation(for: SeatID(rawValue: 1)!)"
    case pendingShowdown = "_ = coordinator.pendingShowdownObservation"
}

private func expectTypecheckFailure(_ probe: HiddenInformationProbe) throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = try coordinatorModulesDirectory(in: packageRoot)
    let source = """
    import PokerCoordinator

    struct SeatID {
        init?(rawValue: Int) {}
    }

    func unavailableTableState() -> TableViewState { fatalError() }
    func unavailableCoordinator() -> CashTableCoordinator { fatalError() }
    let tableState = unavailableTableState()
    let coordinator = unavailableCoordinator()
    \(probe.rawValue)
    """
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("poker-coordinator-boundary-\(UUID().uuidString).swift")
    try source.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "-typecheck", "-I", modules.path, file.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let diagnostics = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    #expect(process.terminationStatus == 1, Comment(rawValue: diagnostics))
    #expect(diagnostics.contains("no such module") == false, Comment(rawValue: diagnostics))
    #expect(
        diagnostics.contains("has no member")
            || diagnostics.contains("is inaccessible due to"),
        Comment(rawValue: diagnostics)
    )
}

private func coordinatorModulesDirectory(in packageRoot: URL) throws -> URL {
    let build = packageRoot.appendingPathComponent(".build", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: build,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    while let candidate = enumerator?.nextObject() as? URL {
        let modules = candidate.deletingLastPathComponent()
        if candidate.lastPathComponent == "PokerCoordinator.swiftmodule",
           modules.lastPathComponent == "Modules" {
            return modules
        }
    }
    throw PublicBoundaryError.modulesNotFound
}

private enum PublicBoundaryError: Error {
    case modulesNotFound
}
