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

        let selection = viewModel.selectSegment(at: 1)

        XCTAssertTrue(selection.appliedDefaultFilters)
        XCTAssertEqual(viewModel.filters, .defaults(sortBy: .name))
    }

    func testASegmentKeepsItsFiltersOnTheNextVisit() {
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: 2)])
        _ = viewModel.selectSegment(at: 1)
        var narrowed = PointOfUseListFilters.defaults(sortBy: .name)
        narrowed.radius = .one
        viewModel.apply(filters: narrowed, searchBounds: bounds)
        _ = viewModel.selectSegment(at: 0)

        let selection = viewModel.selectSegment(at: 1)

        XCTAssertFalse(selection.appliedDefaultFilters)
        XCTAssertEqual(viewModel.filters, narrowed)
    }

    func testNearbyDefaultsToDistanceAndAsksForLocation() {
        location.needsAuthorization = true
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue)])

        let selection = viewModel.selectSegment(at: 1)

        XCTAssertTrue(selection.needsLocationPrompt)
        XCTAssertEqual(viewModel.filters?.sortBy, .distance)
    }

    func testNearbyDoesNotAskOnceLocationIsAuthorized() {
        location.isAuthorized = true
        let viewModel = makeViewModel(segments: [segment(tag: 0), segment(tag: MerchantsListSegment.nearby.rawValue)])

        XCTAssertFalse(viewModel.selectSegment(at: 1).needsLocationPrompt)
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

    func testMerchantMapLeavesOutOnlineMerchants() async {
        let items = [merchant(1, type: .online), merchant(2, type: .physical), merchant(3, type: .onlineAndPhysical)]
        let viewModel = makeViewModel(kind: .merchants, segments: [segment(tag: MerchantsListSegment.all.rawValue, items: items)])
        await waitForReplacedList(of: viewModel)

        XCTAssertEqual(viewModel.items.count, 3)
        XCTAssertEqual(viewModel.mapItems.map(\.id), [2, 3])
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
                         sortOptions: [PointOfUseListFilters.SortBy] = [.name, .distance],
                         items: [ExplorePointOfUse] = []) -> PointOfUseListSegment {
        PointOfUseListSegment(tag: tag,
                              title: "Segment \(tag)",
                              showMap: showMap,
                              showLocationServiceSettings: false,
                              showReversedLocation: false,
                              dataProvider: StubDataProvider(items: items),
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

    init(items: [ExplorePointOfUse]) {
        stubItems = items
        super.init()
    }

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        items = stubItems
        completion(.success(stubItems))
    }
}

private final class StubLocationService: PointOfUseLocationService {
    var isAuthorized = false
    var needsAuthorization = false
    var isPermissionDenied = false
    var currentLocation: CLLocation?

    func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ((String, CLPlacemark?) -> Void)) { }
}
