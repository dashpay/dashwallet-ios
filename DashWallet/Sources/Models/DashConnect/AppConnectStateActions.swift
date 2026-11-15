import Foundation

/// The state-to-actions table (ADR-0019): for each `ConnectionStatus`, the tab
/// its connection is listed on, the status badge, the text key of the status
/// name and the actions it allows. Rows and sheets read this table.
///
/// Disconnect is allowed on Active, Confirming, Not delivered and Expired
/// (spec AC-16). Expired also allows Reconnect, so it offers both: screens
/// SCR-12 `expired` lists Reconnect only, and the spec wins (decided by Roman,
/// 2026-11-06). Remove (no PIN) is the action of Refused only; Reconnect of
/// Disconnected and Expired.
extension AppConnect {
    /// The tab of the Connections page a connection is listed on (AC-13).
    enum Tab: Equatable {
        case active
        case disconnected
        case expired
    }

    /// What a user can do with a connection in a given status.
    enum RowAction: Hashable {
        case disconnect
        case reconnect
        case remove
    }

    /// The colour class of the status dot.
    enum StatusBadge: Equatable {
        case green
        case orange
        case red
        case grey
    }

    enum StateActions {
        struct Row: Equatable {
            let tab: Tab
            let badge: StatusBadge
            /// The English status name, the localization key the status UI uses.
            let textKey: String
            let actions: Set<RowAction>
        }

        /// The row of a status. The switch has no `default`: a status added
        /// later fails to compile until it gets a row.
        static func row(for status: ConnectionStatus) -> Row {
            switch status {
            case .active:
                return Row(tab: .active, badge: .green, textKey: "Active", actions: [.disconnect])
            case .confirming:
                return Row(tab: .active, badge: .orange, textKey: "Confirming", actions: [.disconnect])
            case .undelivered:
                return Row(tab: .active, badge: .orange, textKey: "Not delivered", actions: [.disconnect])
            case .refused:
                return Row(tab: .active, badge: .red, textKey: "Refused", actions: [.remove])
            // TODO(dashconnect-v2-status-ui): screens.md gives Expired no colour; grey keeps it from looking live
            case .expired:
                return Row(tab: .expired, badge: .grey, textKey: "Expired", actions: [.disconnect, .reconnect])
            // TODO(dashconnect-v2-status-ui): screens.md gives Disconnected no colour; grey keeps it from looking live
            case .disconnected:
                return Row(tab: .disconnected, badge: .grey, textKey: "Disconnected (connection status)", actions: [.reconnect])
            }
        }
    }
}
