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

enum HandHistoryDeletionPresentation {
    static let deleteAllMessage = "此操作只会删除牌局存档，余额、统计和账本不会删除。"
    static let confirmDeleteOneIdentifier = "history.confirmDeleteOne"
    static let confirmDeleteAllIdentifier = "history.confirmDeleteAll"
    static let cancelDeleteIdentifier = "history.cancelDelete"

    static func singleMessage(for detail: HandHistoryDetail) -> String {
        "\(detail.tableName) · \(detail.localDay.rawValue) · 第 \(detail.handNumber) 手"
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
