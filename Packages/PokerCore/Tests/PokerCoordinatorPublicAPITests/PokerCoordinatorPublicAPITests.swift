import Foundation
import PokerCoordinator
import Testing

@Test func 普通导入无法访问牌桌与协调器隐藏信息() throws {
    try expectControlSourceTypechecks()
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

    var memberName: String {
        switch self {
        case .deck: "deck"
        case .seed: "seed"
        case .checkpoint: "checkpoint"
        case .opponentHoleCards: "opponentHoleCards"
        case .arbitraryPlayerObservation: "playerObservation"
        case .pendingShowdown: "pendingShowdownObservation"
        }
    }
}

private func expectControlSourceTypechecks() throws {
    let result = try typecheck(probe: nil)
    #expect(result.status == 0, Comment(rawValue: result.diagnostics))
}

private func expectTypecheckFailure(_ probe: HiddenInformationProbe) throws {
    let result = try typecheck(probe: probe)

    #expect(result.status == 1, Comment(rawValue: result.diagnostics))
    #expect(
        result.diagnostics.contains("no such module") == false,
        Comment(rawValue: result.diagnostics)
    )
    #expect(
        result.diagnostics.contains(probe.memberName),
        Comment(rawValue: result.diagnostics)
    )
    #expect(
        result.diagnostics.contains("has no member")
            || result.diagnostics.contains("is inaccessible due to"),
        Comment(rawValue: result.diagnostics)
    )
}

private func typecheck(
    probe: HiddenInformationProbe?
) throws -> (status: Int32, diagnostics: String) {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = try coordinatorModulesDirectory(in: packageRoot)
    let probeSource = probe.map(\.rawValue) ?? ""
    let source = """
    import PokerCoordinator

    struct SeatID {
        init?(rawValue: Int) {}
    }

    func unavailableTableState() -> TableViewState { fatalError() }
    func unavailableCoordinator() -> CashTableCoordinator { fatalError() }
    let tableState = unavailableTableState()
    let coordinator = unavailableCoordinator()
    \(probeSource)
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

    return (process.terminationStatus, diagnostics)
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
