import XCTest
@testable import RiverClub

final class LoadableStateTests: XCTestCase {
    func testLoadingMapsToSkeletonWithoutActions() {
        let state = LoadableState<[Int]>.loading

        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.content)
        XCTAssertFalse(state.showsOfflineBanner)
        XCTAssertFalse(state.allowsRetry)
        XCTAssertFalse(state.showsClearFilters(hasActiveFilters: true, filteredIsEmpty: true))
    }

    func testLoadedEmptyResultOnlyClearsAnActiveFilter() {
        let state = LoadableState<[Int]>.loaded([])

        XCTAssertEqual(state.content, [])
        XCTAssertTrue(state.showsClearFilters(hasActiveFilters: true, filteredIsEmpty: true))
        XCTAssertFalse(state.showsClearFilters(hasActiveFilters: false, filteredIsEmpty: true))
        XCTAssertFalse(state.showsClearFilters(hasActiveFilters: true, filteredIsEmpty: false))
    }

    func testLoadedContentMapsToContentWithoutRecoveryActions() {
        let state = LoadableState.loaded([1, 2])

        XCTAssertEqual(state.content, [1, 2])
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.allowsRetry)
    }

    func testOfflineMapsCachedContentToBannerAndRetry() {
        let state = LoadableState.offline(cached: [1, 2])

        XCTAssertEqual(state.content, [1, 2])
        XCTAssertTrue(state.showsOfflineBanner)
        XCTAssertTrue(state.allowsRetry)
    }

    func testFailedMapsToInlineRetryWithoutContent() {
        let state = LoadableState<[Int]>.failed(message: "网络不可用")

        XCTAssertNil(state.content)
        XCTAssertEqual(state.failureMessage, "网络不可用")
        XCTAssertTrue(state.allowsRetry)
    }

    @MainActor
    func testStateMappingDoesNotChangeSidebarSelection() {
        let session = AppSession()
        session.open(.tables)

        _ = LoadableState<[Int]>.loading.isLoading
        _ = LoadableState.loaded([1]).content
        _ = LoadableState.offline(cached: [1]).showsOfflineBanner
        _ = LoadableState<[Int]>.failed(message: "失败").allowsRetry

        XCTAssertEqual(session.route, .tables)
    }
}
