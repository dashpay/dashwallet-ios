//
//  PointOfUseListViewModelTests.swift
//  DashWalletTests
//
//  The ATM and Where to Spend lists share one view model; the screens only
//  draw it. These pin what moved out of the controllers: the filters a
//  segment opens with, the filter screen's starting sort, the results count,
//  what the map pins, what the details screen gets, and the sync banner.
//

import Combine
import CoreLocation
import MapKit
import XCTest
@testable import dashpay

@MainActor
final class PointOfUseListViewModelTests: XCTestCase {

    private var location: StubLocationService!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        location = StubLocationService()
    }

    override func tearDown() {
        cancellables = []
        super.tearDown()
    }

    // MARK: - Segments

    func testOpensOnTheConfiguredSegmentWithItsFilters() {
        let filters = PointOfUseListFilters.defaults(sortBy: .distance)
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 1)], initialIndex: 1, initialFilters: filters)

        XCTAssertEqual(viewModel.currentSegment.tag, 1)
        XCTAssertEqual(viewModel.filters, filters)
        XCTAssertEqual(viewModel.filterTitle, "Segment 1")
    }

    func testFirstVisitToASegmentAppliesDefaultFilters() {
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 2)])

        let selection = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })

        XCTAssertTrue(selection.appliedDefaultFilters)
        XCTAssertEqual(viewModel.filters, .defaults(sortBy: .name))
    }

    func testASegmentKeepsItsFiltersOnTheNextVisit() {
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 2)])
        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        var narrowed = PointOfUseListFilters.defaults(sortBy: .name)
        narrowed.radius = .one
        viewModel.apply(filters: narrowed, searchBounds: bounds)
        _ = viewModel.selectSegment(at: 0, searchBounds: { _ in self.bounds })

        let selection = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })

        XCTAssertFalse(selection.appliedDefaultFilters)
        XCTAssertEqual(viewModel.filters, narrowed)
    }

    func testNearbyWithoutAMapDefaultsToDistanceAndAsksForLocation() {
        location.needsAuthorization = true
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue, showMap: false)])

        let selection = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })

        XCTAssertTrue(selection.needsLocationPrompt)
        XCTAssertEqual(viewModel.filters?.sortBy, .distance)
    }

    func testNearbyWithAMapLeavesTheLocationPromptToTheMap() {
        location.needsAuthorization = true
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue)])

        let selection = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })

        XCTAssertTrue(viewModel.showsMap)
        XCTAssertFalse(selection.needsLocationPrompt)
    }

    func testAnOlderPlaceNameDoesNotReplaceTheLatestFilterTitle() async {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0, showReversedLocation: true)])

        viewModel.refreshFilterTitle(mapCenter: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        viewModel.refreshFilterTitle(mapCenter: CLLocationCoordinate2D(latitude: 2, longitude: 2))
        location.geocodeCompletions[1]("Newer", nil)
        location.geocodeCompletions[0]("Older", nil)
        await drainMainQueue()

        XCTAssertEqual(viewModel.filterTitle, "Newer")
    }

    func testAPlaceNameDoesNotReturnAfterLocationIsTurnedOff() async {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0, showReversedLocation: true)])

        viewModel.refreshFilterTitle(mapCenter: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        location.isAuthorized = false
        viewModel.refreshFilterTitle(mapCenter: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        location.geocodeCompletions[0]("Older", nil)
        await drainMainQueue()

        XCTAssertEqual(viewModel.filterTitle, "Segment 0")
    }

    func testAPlaceNameDoesNotLandOnAnotherSegment() async {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0, showReversedLocation: true),
                                                 segment(tag: 2, showReversedLocation: true)])

        viewModel.refreshFilterTitle(mapCenter: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        location.geocodeCompletions[0]("Older", nil)
        await drainMainQueue()

        XCTAssertNotEqual(viewModel.filterTitle, "Older")
    }

    func testNearbyDoesNotAskOnceLocationIsAuthorized() {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue)])

        XCTAssertFalse(viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds }).needsLocationPrompt)
    }

    func testFirstVisitFetchesOnceWithTheDefaults() async {
        let nearby = StubDataProvider(items: [atm(1)])
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue, provider: nearby)])

        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        await waitForReplacedList(of: viewModel)

        XCTAssertEqual(nearby.requestedFilters, [.defaults(sortBy: .distance)])
    }

    func testSwitchingSearchesTheAreaOfTheNewRadius() {
        let target = StubDataProvider(items: [])
        var narrowed = PointOfUseListFilters.defaults(sortBy: .name)
        narrowed.radius = .one
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 2, provider: target)])
        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        viewModel.apply(filters: narrowed, searchBounds: bounds)
        _ = viewModel.selectSegment(at: 0, searchBounds: { _ in self.bounds })

        var requestedRadius: CLLocationDistance?
        let area = ExploreMapBounds(rect: MKMapRect(x: 5, y: 5, width: 10, height: 10))
        _ = viewModel.selectSegment(at: 1, searchBounds: { radius in
            requestedRadius = radius
            return area
        })

        XCTAssertEqual(requestedRadius, PointOfUseListFilters.Radius.one.meters)
        XCTAssertEqual(target.requestedBounds.last, area)
    }

    // MARK: - Location

    func testAFixNearTheLastOneDoesNotRefetch() {
        let provider = StubDataProvider(items: [])
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        let start = CLLocation(latitude: 40.758, longitude: -73.985)
        viewModel.locationDidChange(to: start, bounds: bounds)
        let requests = provider.requestedFilters.count

        viewModel.locationDidChange(to: CLLocation(latitude: 40.7585, longitude: -73.985), bounds: bounds)

        XCTAssertEqual(provider.requestedFilters.count, requests)
    }

    func testAFixAfterPanningRefetchesForTheDevice() {
        let provider = StubDataProvider(items: [])
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        let start = CLLocation(latitude: 40.758, longitude: -73.985)
        viewModel.locationDidChange(to: start, bounds: bounds)
        viewModel.mapDidMove(center: CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5), bounds: bounds)
        let requests = provider.requestedFilters.count

        viewModel.locationDidChange(to: CLLocation(latitude: 40.7585, longitude: -73.985), bounds: bounds)

        XCTAssertEqual(provider.requestedFilters.count, requests + 1)
        XCTAssertNil(viewModel.searchCenterCoordinate)
    }

    // MARK: - Filter screen

    func testFilterScreenReplacesASortTheSegmentDoesNotOffer() {
        var filters = PointOfUseListFilters.defaults(sortBy: .distance)
        filters.radius = .five
        let viewModel = makeViewModel(segments: [segment(tag: 0, sortOptions: [.name, .discount])], initialFilters: filters)

        let editing = viewModel.filtersForEditing

        XCTAssertEqual(editing.sortBy, .name)
        XCTAssertEqual(editing.radius, .five)
    }

    func testFilterScreenWithoutFiltersStartsWithOnlyTheSegmentSort() {
        let viewModel = makeViewModel(segments: [segment(tag: MerchantsListSegment.nearby.rawValue)])

        XCTAssertEqual(viewModel.filtersForEditing, PointOfUseListFilters(sortBy: .distance))
    }

    // MARK: - Results count

    func testAtmCountShowsWithLocation() async {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0, items: [atm(1), atm(2)])])
        await waitForReplacedList(of: viewModel)

        XCTAssertTrue(viewModel.resultsSubtitle?.hasPrefix("2 ATM") == true, viewModel.resultsSubtitle ?? "nil")
    }

    func testNoCountWithoutLocation() async {
        let viewModel = makeViewModel(segments: [segment(tag: 0, items: [atm(1)])])
        await waitForReplacedList(of: viewModel)

        XCTAssertNil(viewModel.resultsSubtitle)
    }

    func testNoMerchantCountOnAll() async {
        location.isAuthorized = true
        let all = segment(tag: MerchantsListSegment.all.rawValue, items: [merchant(1, type: .physical)])
        let viewModel = makeViewModel(kind: .merchants, segments: [all])
        await waitForReplacedList(of: viewModel)

        XCTAssertNil(viewModel.resultsSubtitle)
    }

    // MARK: - Map

    func testAtmMapPinsEveryRow() async {
        let viewModel = makeViewModel(segments: [segment(tag: 0, items: [atm(1), atm(2)])])
        await waitForReplacedList(of: viewModel)

        XCTAssertEqual(viewModel.mapItems.map(\.id), [1, 2])
    }

    func testAtmMapPinsAnAppendedPage() async {
        let provider = StubDataProvider(items: [atm(1)], nextPage: [atm(2)])
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        await waitForReplacedList(of: viewModel)
        let appended = expectation(description: "page appended")
        viewModel.listUpdates
            .filter { $0 == .appended }
            .first()
            .sink { _ in appended.fulfill() }
            .store(in: &cancellables)

        viewModel.fetchNextPage()
        await fulfillment(of: [appended], timeout: 2)

        XCTAssertEqual(viewModel.mapItems.map(\.id), [1, 2])
    }

    func testMerchantMapLeavesOutOnlineMerchants() async {
        let items = [merchant(1, type: .online), merchant(2, type: .physical), merchant(3, type: .onlineAndPhysical)]
        let viewModel = makeViewModel(kind: .merchants, segments: [segment(tag: MerchantsListSegment.all.rawValue, items: items)])
        await waitForReplacedList(of: viewModel)

        XCTAssertEqual(viewModel.items.count, 3)
        XCTAssertEqual(viewModel.mapItems.map(\.id), [2, 3])
    }

    /// Without a location the merchant map pins the loaded rows, so a page
    /// adds its physical merchants.
    func testMerchantMapPinsAnAppendedPageWithoutALocation() async {
        let provider = StubDataProvider(items: [merchant(1, type: .physical)],
                                        nextPage: [merchant(2, type: .online), merchant(3, type: .physical)])
        let viewModel = makeViewModel(kind: .merchants,
                                      segments: [segment(tag: MerchantsListSegment.all.rawValue, provider: provider)])
        await waitForReplacedList(of: viewModel)
        let appended = expectation(description: "page appended")
        viewModel.listUpdates
            .filter { $0 == .appended }
            .first()
            .sink { _ in appended.fulfill() }
            .store(in: &cancellables)

        viewModel.fetchNextPage()
        await fulfillment(of: [appended], timeout: 2)

        XCTAssertEqual(viewModel.mapItems.map(\.id), [1, 3])
    }

    func testNoPinsForASegmentWithoutAMap() async {
        let viewModel = makeViewModel(segments: [segment(tag: 0, showMap: false, items: [atm(1)])])
        await waitForReplacedList(of: viewModel)

        XCTAssertTrue(viewModel.mapItems.isEmpty)
    }

    // MARK: - Details

    func testAtmDetailsSearchTheDefaultRadius() {
        let viewModel = makeViewModel(segments: [segment(tag: 0)])

        let request = viewModel.detailsRequest(for: atm(1))

        XCTAssertEqual(request?.searchRadius, kDefaultRadius)
        XCTAssertEqual(request?.isShowAllHidden, true)
    }

    func testMerchantDetailsOnAllAreNotLimitedToTheRadius() {
        let viewModel = makeViewModel(kind: .merchants,
                                      segments: [segment(tag: MerchantsListSegment.all.rawValue)],
                                      initialFilters: .defaults(sortBy: .name))

        let request = viewModel.detailsRequest(for: merchant(1, type: .physical))

        XCTAssertEqual(request?.searchRadius, .greatestFiniteMagnitude)
        XCTAssertEqual(request?.isShowAllHidden, false)
    }

    func testMerchantDetailsOnNearbyUseTheFilterRadius() {
        var filters = PointOfUseListFilters.defaults(sortBy: .distance)
        filters.radius = .five
        let viewModel = makeViewModel(kind: .merchants,
                                      segments: [segment(tag: MerchantsListSegment.nearby.rawValue)],
                                      initialFilters: filters)

        XCTAssertEqual(viewModel.detailsRequest(for: merchant(1, type: .physical))?.searchRadius,
                       PointOfUseListFilters.Radius.five.meters)
    }

    func testOnlineMerchantDetailsHideShowAll() {
        let viewModel = makeViewModel(kind: .merchants, segments: [segment(tag: MerchantsListSegment.online.rawValue)])

        XCTAssertEqual(viewModel.detailsRequest(for: merchant(1, type: .online))?.isShowAllHidden, true)
    }

    func testWhereToSpendOpensNoDetailsForANonMerchant() {
        let viewModel = makeViewModel(kind: .merchants, segments: [segment(tag: 0)])

        XCTAssertNil(viewModel.detailsRequest(for: atm(1)))
    }

    // MARK: - Sync banner

    func testSyncBannerShowsWithoutADatabase() {
        let viewModel = makeViewModel(segments: [segment(tag: 0)])

        viewModel.refreshSyncBanner()

        XCTAssertTrue(viewModel.isSyncBannerVisible)
    }

    func testSyncBannerHidesWhenTheDatabaseUpdates() {
        let notificationCenter = NotificationCenter()
        let viewModel = makeViewModel(segments: [segment(tag: 0)], notificationCenter: notificationCenter)
        viewModel.refreshSyncBanner()
        let hidden = expectation(description: "banner hidden")
        viewModel.$isSyncBannerVisible
            .dropFirst()
            .sink { isVisible in if !isVisible { hidden.fulfill() } }
            .store(in: &cancellables)

        notificationCenter.post(name: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil)

        wait(for: [hidden], timeout: 1)
    }

    func testADatabaseUpdateClearsEverySegment() async {
        let notificationCenter = NotificationCenter()
        let other = StubDataProvider(items: [atm(9)])
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 2, provider: other)],
                                      notificationCenter: notificationCenter)
        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        await drainMainQueue()
        _ = viewModel.selectSegment(at: 0, searchBounds: { _ in self.bounds })
        XCTAssertFalse(other.items.isEmpty)

        // Segment switches publish rows too; wait for the update that comes
        // after the cache was cleared.
        let cleared = expectation(description: "every segment cleared")
        viewModel.listUpdates
            .filter { _ in other.items.isEmpty }
            .first()
            .sink { _ in cleared.fulfill() }
            .store(in: &cancellables)

        notificationCenter.post(name: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil)

        await fulfillment(of: [cleared], timeout: 3)
    }

    // MARK: - Stale responses

    func testALateResponseDoesNotReplaceNewerRows() async {
        let provider = DeferredDataProvider()
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        viewModel.search(query: "newer")

        provider.completeFirstPage(1, with: [atm(2)])
        provider.completeFirstPage(0, with: [atm(1)])
        await drainMainQueue()

        XCTAssertEqual(viewModel.items.map(\.id), [2])
    }

    /// An earlier empty response does not end the loading state, so "no
    /// results" does not flash while the newer request is still running.
    func testALateResponseDoesNotEndLoading() async {
        let provider = DeferredDataProvider()
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)],
                                      initialFilters: .defaults(sortBy: .name))
        viewModel.search(query: "newer")

        provider.completeFirstPage(0, with: [])
        await drainMainQueue()

        XCTAssertFalse(viewModel.showsEmptyResults)
    }

    func testAPageThatLandsAfterANewSearchIsDropped() async {
        let provider = DeferredDataProvider()
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        provider.completeFirstPage(0, with: [atm(1)])
        await drainMainQueue()
        viewModel.fetchNextPage()
        viewModel.search(query: "newer")

        provider.completeFirstPage(1, with: [atm(5)])
        provider.completeNextPage(0, with: [atm(2)])
        await drainMainQueue()

        XCTAssertEqual(viewModel.items.map(\.id), [5])
    }

    /// The provider and the list take a page in the same main-queue turn, so
    /// a search that starts right after cannot leave the provider holding a
    /// page the list dropped. If that search then fails, both still show the
    /// same rows, and the next page continues from them.
    func testAProviderAndTheListAgreeAfterASearchThatFails() async {
        let provider = PagingProvider()
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: provider)])
        provider.answerFirstPage(0, with: .success([atm(1)]))
        await drainMainQueue()

        viewModel.fetchNextPage()
        // The provider takes the page in the next main-queue turn; the search
        // is queued right behind it, so it starts in the turn after that.
        provider.answerNextPage(0, with: [atm(2)])
        DispatchQueue.main.async { viewModel.search(query: "fails") }
        await drainMainQueue()
        provider.answerFirstPage(1, with: .failure(StubError()))
        await drainMainQueue()

        XCTAssertEqual(viewModel.items.map(\.id), provider.items.map(\.id))
        XCTAssertEqual(viewModel.items.map(\.id), [1, 2])
        XCTAssertEqual(provider.currentPage?.offset, 1, "The next page must continue after the rows on screen")
    }

    /// A provider records the parameters of a request only with its rows, so
    /// an identical request made while the first is in flight is not answered
    /// from the previous request's rows.
    func testAProviderRecordsParametersOnlyWithItsRows() async {
        let provider = PointOfUseDataProvider()
        let page = PaginationResult<ExplorePointOfUse>(items: [atm(1)], offset: 0)

        provider.handleFirstPage(request: provider.beginRequest(), result: .failure(StubError()), query: "q",
                                 bounds: bounds, userPoint: nil, filters: nil) { _ in }
        await drainMainQueue()
        XCTAssertNil(provider.lastQuery)

        provider.handleFirstPage(request: provider.beginRequest(), result: .success(page), query: "q",
                                 bounds: bounds, userPoint: nil, filters: nil) { _ in }
        await drainMainQueue()
        XCTAssertEqual(provider.lastQuery, "q")
        XCTAssertEqual(provider.lastBounds, bounds)
        XCTAssertEqual(provider.items.map(\.id), [1])
    }

    /// A first page that lands after a newer request leaves the provider as
    /// the newer request set it, so the next page continues that request.
    func testAProviderIgnoresASupersededFirstPage() async {
        let provider = PointOfUseDataProvider()
        let older = provider.beginRequest()
        let newer = provider.beginRequest()
        var calls: [String] = []

        provider.handleFirstPage(request: newer, result: .success(PaginationResult(items: [atm(2)], offset: 0)),
                                 query: "newer", bounds: bounds, userPoint: nil, filters: nil) { _ in calls.append("newer") }
        provider.handleFirstPage(request: older, result: .success(PaginationResult(items: [atm(1)], offset: 40)),
                                 query: "older", bounds: nil, userPoint: nil, filters: nil) { _ in calls.append("older") }
        await drainMainQueue()

        XCTAssertEqual(provider.items.map(\.id), [2])
        XCTAssertEqual(provider.lastQuery, "newer")
        XCTAssertEqual(provider.lastBounds, bounds)
        XCTAssertEqual(provider.currentPage?.offset, 0)
        XCTAssertEqual(calls, ["newer"], "A superseded response must not reach its caller")
    }

    /// A page that lands after a new first page was requested does not append
    /// to the new rows or move the paging offset.
    func testAProviderIgnoresAPageAfterANewRequest() async {
        let provider = PointOfUseDataProvider()
        provider.handleFirstPage(request: provider.beginRequest(), result: .success(PaginationResult(items: [atm(1)], offset: 0)),
                                 query: "q", bounds: bounds, userPoint: nil, filters: nil) { _ in }
        await drainMainQueue()

        let page = provider.beginRequest()
        let refresh = provider.beginRequest()
        provider.handle(request: page, result: .success(PaginationResult(items: [atm(9)], offset: 1)), appending: true) { _ in }
        provider.handleFirstPage(request: refresh, result: .success(PaginationResult(items: [atm(3)], offset: 0)),
                                 query: "q", bounds: bounds, userPoint: nil, filters: nil) { _ in }
        await drainMainQueue()

        XCTAssertEqual(provider.items.map(\.id), [3])
        XCTAssertEqual(provider.currentPage?.offset, 0)
    }

    /// Clearing the cache supersedes a request in flight.
    func testClearingACacheDropsTheResponseInFlight() async {
        let provider = PointOfUseDataProvider()
        let request = provider.beginRequest()
        provider.clearCache()

        provider.handleFirstPage(request: request, result: .success(PaginationResult(items: [atm(1)], offset: 0)),
                                 query: "q", bounds: bounds, userPoint: nil, filters: nil) { _ in }
        await drainMainQueue()

        XCTAssertTrue(provider.items.isEmpty)
        XCTAssertNil(provider.lastQuery)
    }

    /// Leaving a segment supersedes its request in flight: a page that lands
    /// after the switch changes neither its rows nor its paging offset, so
    /// coming back shows, and pages from, the rows the list last showed.
    func testSwitchingSegmentsDropsTheOutgoingPage() async {
        let all = PagingProvider()
        let nearby = PagingProvider()
        let viewModel = makeViewModel(segments: [segment(tag: 0, provider: all), segment(tag: 1, provider: nearby)])
        all.answerFirstPage(0, with: .success([atm(1)]))
        await drainMainQueue()

        viewModel.fetchNextPage()
        _ = viewModel.selectSegment(at: 1, searchBounds: { _ in self.bounds })
        all.answerNextPage(0, with: [atm(2)])
        await drainMainQueue()

        XCTAssertEqual(all.items.map(\.id), [1])
        XCTAssertEqual(all.currentPage?.offset, 0, "Paging must continue after the rows the list showed")
    }

    /// A request made again while the first is still in flight is not
    /// answered from the rows of the request before it.
    func testAllMerchantsFetchesARepeatedPendingQuery() async {
        let provider = DeferredAllMerchantsProvider()
        var answers: [[Int64]] = []
        let record: (Result<[ExplorePointOfUse], Error>) -> Void = { answers.append((try? $0.get())?.map(\.id) ?? []) }
        provider.items(query: "a", in: nil, userPoint: nil, with: nil, completion: record)
        provider.completeFetch(0, with: [atm(1)])
        await drainMainQueue()

        provider.items(query: "b", in: nil, userPoint: nil, with: nil, completion: record)
        provider.items(query: "b", in: nil, userPoint: nil, with: nil, completion: record)
        await drainMainQueue()

        XCTAssertEqual(provider.fetchCount, 3, "The repeated b request must fetch, not read a's rows")
        XCTAssertEqual(answers, [[1]])
    }

    // MARK: - Helpers

    private let bounds = ExploreMapBounds(rect: MKMapRect(x: 0, y: 0, width: 1000, height: 1000))

    private func makeViewModel(kind: PointOfUseListConfiguration.Kind = .atms,
                               segments: [PointOfUseListSegment],
                               initialIndex: Int = 0,
                               initialFilters: PointOfUseListFilters? = nil,
                               notificationCenter: NotificationCenter = NotificationCenter()) -> PointOfUseListViewModel {
        let configuration = PointOfUseListConfiguration(kind: kind,
                                                        segments: segments,
                                                        initialSegmentIndex: initialIndex,
                                                        initialFilters: initialFilters,
                                                        locationServicePopupTitle: "",
                                                        locationServicePopupDetails: "")
        let missingDatabase = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-explore-\(UUID().uuidString).db")
        return PointOfUseListViewModel(configuration: configuration,
                                       location: location,
                                       databaseURL: missingDatabase,
                                       notificationCenter: notificationCenter)
    }

    /// Providers answer on the main queue; this returns once everything
    /// queued before it has run.
    private func drainMainQueue() async {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }

    private func waitForReplacedList(of viewModel: PointOfUseListViewModel) async {
        let replaced = expectation(description: "list replaced")
        viewModel.listUpdates
            .filter { $0 == .replaced }
            .first()
            .sink { _ in replaced.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [replaced], timeout: 2)
    }

    private func segment(tag: Int,
                         showMap: Bool = true,
                         showReversedLocation: Bool = false,
                         sortOptions: [PointOfUseListFilters.SortBy] = [.name, .distance],
                         items: [ExplorePointOfUse] = [],
                         provider: PointOfUseDataProvider? = nil) -> PointOfUseListSegment {
        PointOfUseListSegment(tag: tag,
                              title: "Segment \(tag)",
                              showMap: showMap,
                              showLocationServiceSettings: false,
                              showReversedLocation: showReversedLocation,
                              dataProvider: provider ?? StubDataProvider(items: items),
                              filterGroups: [],
                              territoriesDataSource: nil,
                              sortOptions: sortOptions)
    }

    private func atm(_ id: Int64) -> ExplorePointOfUse {
        pointOfUse(id, category: .unknown)
    }

    private func merchant(_ id: Int64, type: ExplorePointOfUse.Merchant.`Type`) -> ExplorePointOfUse {
        let merchant = ExplorePointOfUse.Merchant(merchantId: "\(id)", paymentMethod: .dash, type: type, deeplink: nil,
                                                  savingsBasisPoints: 0, denominationsType: nil, redeemType: nil)
        return pointOfUse(id, category: .merchant(merchant))
    }

    private func pointOfUse(_ id: Int64, category: ExplorePointOfUse.Category) -> ExplorePointOfUse {
        ExplorePointOfUse(id: id, name: "Place \(id)", category: category, active: true, city: nil, territory: nil,
                          address1: nil, address2: nil, address3: nil, address4: nil, latitude: nil, longitude: nil,
                          website: nil, phone: nil, logoLocation: nil, coverImage: nil, source: nil)
    }
}

// MARK: - Test doubles

private final class StubDataProvider: PointOfUseDataProvider {
    private let stubItems: [ExplorePointOfUse]
    private let stubNextPage: [ExplorePointOfUse]
    private(set) var requestedFilters: [PointOfUseListFilters?] = []
    private(set) var requestedBounds: [ExploreMapBounds?] = []

    init(items: [ExplorePointOfUse], nextPage: [ExplorePointOfUse] = []) {
        stubItems = items
        stubNextPage = nextPage
        super.init()
    }

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        requestedFilters.append(filters)
        requestedBounds.append(bounds)
        // Like every provider, answers on the main queue in a later turn.
        DispatchQueue.main.async { [self] in
            items = stubItems
            completion(.success(stubItems))
        }
    }

    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        DispatchQueue.main.async { [self] in
            items += stubNextPage
            completion(.success(stubNextPage))
        }
    }
}

/// Holds every request until the test answers it, in any order.
private final class DeferredDataProvider: PointOfUseDataProvider {
    private var firstPages: [(Result<[ExplorePointOfUse], Error>) -> Void] = []
    private var nextPages: [(Result<[ExplorePointOfUse], Error>) -> Void] = []

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        firstPages.append(completion)
    }

    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        nextPages.append(completion)
    }

    func completeFirstPage(_ index: Int, with items: [ExplorePointOfUse]) {
        firstPages[index](.success(items))
    }

    func completeNextPage(_ index: Int, with items: [ExplorePointOfUse]) {
        nextPages[index](.success(items))
    }
}

/// A provider that answers through the real `PointOfUseDataProvider` commit
/// path, held until the test answers it.
private final class PagingProvider: PointOfUseDataProvider {
    private var firstPages: [(Int, (Result<[ExplorePointOfUse], Error>) -> Void)] = []
    private var nextPages: [(Int, (Result<[ExplorePointOfUse], Error>) -> Void)] = []

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        firstPages.append((beginRequest(), completion))
    }

    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        nextPages.append((beginRequest(), completion))
    }

    func answerFirstPage(_ index: Int, with result: Result<[ExplorePointOfUse], Error>) {
        let (request, completion) = firstPages[index]
        handleFirstPage(request: request, result: result.map { PaginationResult(items: $0, offset: 0) },
                        query: nil, bounds: nil, userPoint: nil, filters: nil, completion: completion)
    }

    func answerNextPage(_ index: Int, with items: [ExplorePointOfUse]) {
        let (request, completion) = nextPages[index]
        handle(request: request, result: .success(PaginationResult(items: items, offset: self.items.count)),
               appending: true, completion: completion)
    }
}

/// The All merchants provider with its database fetch held until the test
/// answers it.
private final class DeferredAllMerchantsProvider: AllMerchantsDataProvider {
    private var fetches: [(Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void] = []
    var fetchCount: Int { fetches.count }

    override func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?, offset: Int,
                        completion: @escaping (Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        fetches.append(completion)
    }

    func completeFetch(_ index: Int, with items: [ExplorePointOfUse]) {
        fetches[index](.success(PaginationResult(items: items, offset: 0)))
    }
}

private struct StubError: Error { }

private final class StubLocationService: PointOfUseLocationService {
    var isAuthorized = false
    var needsAuthorization = false
    var isPermissionDenied = false
    var currentLocation: CLLocation?

    /// Each request's completion, in request order; a test answers them.
    var geocodeCompletions: [(String, CLPlacemark?) -> Void] = []

    func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ((String, CLPlacemark?) -> Void)) {
        geocodeCompletions.append(completion)
    }
}
