import PokerCore
import PokerSession

enum HandHistoryDateSelection: Equatable, Sendable {
    case all
    case today
    case lastSevenDays
    case custom(LocalDay)
}

struct HandHistoryFilters: Equatable, Sendable {
    var table: TableID?
    var dateSelection: HandHistoryDateSelection

    init(
        table: TableID? = nil,
        dateSelection: HandHistoryDateSelection = .all
    ) {
        self.table = table
        self.dateSelection = dateSelection
    }
}

enum HandHistoryLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded([HandHistoryListItem])
    case failed(String)
}

enum HandHistoryPendingDeletion: Equatable, Sendable {
    case hand(HandID)
    case all
}

struct HandHistoryDeletionOverlay: Equatable, Sendable {
    let pendingDeletion: HandHistoryPendingDeletion
    let title: String
    let message: String
    let confirmationTitle: String
    let confirmationIdentifier: String
}

enum HandHistoryDeletionPresentation {
    static let deleteAllMessage = "此操作只会删除牌局存档，余额、统计和账本不会删除。"
    static let confirmDeleteOneIdentifier = "history.confirmDeleteOne"
    static let confirmDeleteAllIdentifier = "history.confirmDeleteAll"
    static let cancelDeleteIdentifier = "history.cancelDelete"

    static func singleMessage(for detail: HandHistoryDetail) -> String {
        "\(detail.tableName) · \(detail.localDay.rawValue) · 第 \(detail.handNumber) 手"
    }

    static func overlay(
        for state: HandHistoryViewState
    ) -> HandHistoryDeletionOverlay? {
        guard let pendingDeletion = state.pendingDeletion else { return nil }
        let overlay: HandHistoryDeletionOverlay
        switch pendingDeletion {
        case let .hand(id):
            let message: String
            if let detail = state.selection, detail.id == id {
                message = singleMessage(for: detail)
            } else if let item = state.items.first(where: { $0.id == id }) {
                message = "\(item.tableName) · \(item.localDay.rawValue) · 第 \(item.handNumber) 手"
            } else {
                return nil
            }
            overlay = HandHistoryDeletionOverlay(
                pendingDeletion: pendingDeletion,
                title: "删除本局存档？",
                message: message,
                confirmationTitle: "删除本局",
                confirmationIdentifier: confirmDeleteOneIdentifier
            )
        case .all:
            overlay = HandHistoryDeletionOverlay(
                pendingDeletion: pendingDeletion,
                title: "清空全部牌局存档？",
                message: deleteAllMessage,
                confirmationTitle: "清空全部",
                confirmationIdentifier: confirmDeleteAllIdentifier
            )
        }
        guard let deletionError = state.deletionError else { return overlay }
        return HandHistoryDeletionOverlay(
            pendingDeletion: overlay.pendingDeletion,
            title: overlay.title,
            message: "\(overlay.message)\n\(deletionError)",
            confirmationTitle: overlay.confirmationTitle,
            confirmationIdentifier: overlay.confirmationIdentifier
        )
    }
}

struct HandHistoryViewState: Equatable, Sendable {
    var filters: HandHistoryFilters
    var loadState: HandHistoryLoadState
    var availableTables: [HandHistoryTableOption]
    var selection: HandHistoryDetail?
    var pendingDeletion: HandHistoryPendingDeletion?
    var deletionError: String?

    init(
        filters: HandHistoryFilters = HandHistoryFilters(),
        loadState: HandHistoryLoadState = .idle,
        availableTables: [HandHistoryTableOption] = [],
        selection: HandHistoryDetail? = nil,
        pendingDeletion: HandHistoryPendingDeletion? = nil,
        deletionError: String? = nil
    ) {
        self.filters = filters
        self.loadState = loadState
        self.availableTables = availableTables
        self.selection = selection
        self.pendingDeletion = pendingDeletion
        self.deletionError = deletionError
    }

    var items: [HandHistoryListItem] {
        guard case let .loaded(items) = loadState else { return [] }
        return items
    }
}
