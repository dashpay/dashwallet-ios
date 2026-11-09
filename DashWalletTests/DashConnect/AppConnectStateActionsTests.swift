import DashUIKit
import Foundation
import SwiftUI
import XCTest
@testable import dashpay

/// The state-to-actions table: what each `ConnectionStatus` shows (tab, badge,
/// text) and allows (Disconnect, Reconnect, Remove) (`AppConnectStateActions.swift`,
/// ADR 0010).
///
/// Rules the table is held to:
/// - Tab (spec §5 AC-13): "Confirming, Not delivered and Refused connections are on
///   Active with their status"; Expired and Disconnected have their own tabs.
/// - Disconnect (spec §5 AC-16): "a wallet user with an Active, Confirming, Not
///   delivered or Expired connection" can confirm Disconnect; AC-20: Confirming and
///   Not delivered have "Disconnect as its only action".
/// - Remove (spec §5 AC-20b, screens SCR-12 `refused`): a Refused connection "offers to
///   remove it"; Remove is its action and no other status offers it.
/// - Reconnect (spec §5 AC-19; screens SCR-04 "Reconnect on Disconnected and Expired",
///   SCR-12 `disconnected` and `expired`): Disconnected and Expired offer it, no other
///   status does.
/// - Expired offers Disconnect and Reconnect: screens SCR-12 `expired` lists Reconnect
///   only, spec AC-16 also allows Disconnect on Expired; the spec wins (T5 edge case).
/// - Badge (screens SCR-12): Active shows a green status, Confirming and Not delivered
///   an orange one, Refused a red one. The screens give no colour for Expired and
///   Disconnected; they only must not look live.
/// - Text key: the English status name, the localization key the status UI already uses.
final class AppConnectStateActionsTests: XCTestCase {
    private typealias Table = AppConnect.StateActions

    func testActiveRow() {
        let row = Table.row(for: .active)
        XCTAssertEqual(row.tab, .active)
        XCTAssertEqual(row.badge, .green)
        XCTAssertEqual(row.textKey, "Active")
        XCTAssertEqual(row.actions, [.disconnect])
    }

    func testConfirmingRow() {
        let row = Table.row(for: .confirming)
        XCTAssertEqual(row.tab, .active)
        XCTAssertEqual(row.badge, .orange)
        XCTAssertEqual(row.textKey, "Confirming")
        XCTAssertEqual(row.actions, [.disconnect])
    }

    func testUndeliveredRow() {
        let row = Table.row(for: .undelivered)
        XCTAssertEqual(row.tab, .active)
        XCTAssertEqual(row.badge, .orange)
        XCTAssertEqual(row.textKey, "Not delivered")
        XCTAssertEqual(row.actions, [.disconnect])
    }

    func testRefusedRow() {
        let row = Table.row(for: .refused)
        XCTAssertEqual(row.tab, .active)
        XCTAssertEqual(row.badge, .red)
        XCTAssertEqual(row.textKey, "Refused")
        XCTAssertEqual(row.actions, [.remove])
    }

    func testExpiredRow() {
        let row = Table.row(for: .expired)
        XCTAssertEqual(row.tab, .expired)
        XCTAssertNotEqual(row.badge, .green)
        XCTAssertEqual(row.textKey, "Expired")
        XCTAssertEqual(row.actions, [.disconnect, .reconnect])
    }

    func testDisconnectedRow() {
        let row = Table.row(for: .disconnected)
        XCTAssertEqual(row.tab, .disconnected)
        XCTAssertNotEqual(row.badge, .green)
        XCTAssertEqual(row.textKey, "Disconnected (connection status)")
        XCTAssertEqual(row.actions, [.reconnect])
    }

    func testNoStatusOffersAnActionTheSpecForbidsForIt() {
        let disconnectable: Set<ConnectionStatus> = [.active, .confirming, .undelivered, .expired]
        let reconnectable: Set<ConnectionStatus> = [.disconnected, .expired]
        let removable: Set<ConnectionStatus> = [.refused]

        for status in ConnectionStatus.allCases {
            let actions = Table.row(for: status).actions
            XCTAssertEqual(actions.contains(.disconnect), disconnectable.contains(status),
                           "Disconnect for \(status)")
            XCTAssertEqual(actions.contains(.reconnect), reconnectable.contains(status),
                           "Reconnect for \(status)")
            XCTAssertEqual(actions.contains(.remove), removable.contains(status),
                           "Remove for \(status)")
            XCTAssertFalse(actions.isEmpty, "\(status) must offer an action")
        }
    }

    func testEachStatusHasOneTabAndTheActiveTabHoldsExactlyTheLiveAndPendingOnes() {
        let onActive = Set(ConnectionStatus.allCases.filter { Table.row(for: $0).tab == .active })
        XCTAssertEqual(onActive, [.active, .confirming, .undelivered, .refused])
    }

    func testTextKeysAreDistinct() {
        let keys = ConnectionStatus.allCases.map { Table.row(for: $0).textKey }
        XCTAssertEqual(Set(keys).count, ConnectionStatus.allCases.count)
    }
}

// MARK: - What the Connections row and badge show (T27: R8, R20)

/// The row reads the table (ADR 0010) instead of showing Disconnect for every
/// status, and the badge names and colours a status by the table.
final class ConnectionRowStatusTests: XCTestCase {
    func testTheRowOffersExactlyTheActionsOfTheTable() {
        for status in ConnectionStatus.allCases {
            XCTAssertEqual(
                ConnectionRow.actions(for: status), AppConnect.StateActions.row(for: status).actions,
                "row actions for \(status)")
        }
    }

    func testARefusedRowOffersRemoveAndNoDisconnect() {
        let actions = ConnectionRow.actions(for: .refused)
        XCTAssertEqual(actions, [.remove])
        XCTAssertFalse(actions.contains(.disconnect))
    }

    func testLiveAndPendingRowsAndAnExpiredRowOfferDisconnect() {
        for status: ConnectionStatus in [.active, .confirming, .undelivered, .expired] {
            XCTAssertTrue(ConnectionRow.actions(for: status).contains(.disconnect), "\(status)")
        }
        XCTAssertFalse(ConnectionRow.actions(for: .disconnected).contains(.disconnect))
    }

    func testTheBadgeNamesRefusedAndExpiredWithTheLocalizedTable() {
        XCTAssertEqual(ConnectionStatusBadge.label(for: .refused), NSLocalizedString("Refused", comment: ""))
        XCTAssertEqual(ConnectionStatusBadge.label(for: .expired), NSLocalizedString("Expired", comment: ""))
        // Not the raw enum value.
        XCTAssertNotEqual(ConnectionStatusBadge.label(for: .refused), ConnectionStatus.refused.rawValue)
        XCTAssertNotEqual(ConnectionStatusBadge.label(for: .expired), ConnectionStatus.expired.rawValue)
    }

    /// T34 F13: the Coinbase entry point reads the shared "Disconnected" key, so
    /// the badge owns a DashConnect key, "Disconnected (connection status)",
    /// whose English value stays "Disconnected".
    func testTheDisconnectedBadgeReadsItsOwnKeyAndStillShowsDisconnected() {
        let ownKey = "Disconnected (connection status)"
        let localized = Bundle.main.localizedString(forKey: ownKey, value: "MISSING-KEY", table: nil)

        XCTAssertEqual(localized, "Disconnected", "the key \(ownKey) has an entry in Localizable.strings")
        XCTAssertEqual(ConnectionStatusBadge.label(for: .disconnected), localized)
    }

    /// T38 (G7): the table names the badge's own Disconnected key, not the
    /// shared one, so a translation that tells them apart cannot drift.
    func testTheTablesDisconnectedRowNamesTheBadgesOwnKey() {
        XCTAssertEqual(AppConnect.StateActions.row(for: .disconnected).textKey, "Disconnected (connection status)")
    }

    func testTheBadgeLabelIsTheTablesTextKeyLocalizedForEveryStatus() {
        for status in ConnectionStatus.allCases {
            XCTAssertEqual(
                ConnectionStatusBadge.label(for: status),
                Bundle.main.localizedString(forKey: AppConnect.StateActions.row(for: status).textKey, value: nil, table: nil), "\(status)")
        }
    }

    func testARefusedRowHasARedDotAndTheOthersFollowTheTable() {
        XCTAssertEqual(ConnectionStatusBadge.dotColor(for: .refused), Color.dash.red)
        XCTAssertEqual(ConnectionStatusBadge.dotColor(for: .active), Color.dash.green)
        XCTAssertEqual(ConnectionStatusBadge.dotColor(for: .undelivered), Color.dash.orange)
        XCTAssertNotEqual(ConnectionStatusBadge.dotColor(for: .expired), Color.dash.blue)
        XCTAssertNotEqual(ConnectionStatusBadge.dotColor(for: .disconnected), Color.dash.blue)
    }
}
