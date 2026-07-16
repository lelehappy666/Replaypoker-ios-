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

struct HandHistoryViewState: Equatable, Sendable {
    var filters: HandHistoryFilters
    var loadState: HandHistoryLoadState

    init(
        filters: HandHistoryFilters = HandHistoryFilters(),
        loadState: HandHistoryLoadState = .idle
    ) {
        self.filters = filters
        self.loadState = loadState
    }
}
