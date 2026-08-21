//
//  TransferPrivacyTip.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// The note under the confirm sheet's summary: what this particular route means
/// for privacy, or how long the money takes to become spendable.
///
/// Route in, copy out — it reads nothing else, which is why it is a view of its
/// own rather than eighty lines inside a sheet that also runs a transfer. Each
/// of the six routes can be looked at on its own in the canvas.
///
/// The drawing is `DashUIKit.SystemMessageView`; what stays here is the mapping
/// from route to words, which is the app's and not the design system's.
struct TransferPrivacyTip: View {
    let route: InternalTransferRoute
    /// `.platformToCore` only: the amount is the whole balance, which the copy
    /// says out loud.
    var isFullWithdrawal: Bool = false

    var body: some View {
        DashUIKit.SystemMessageView(
            title: title,
            subtitle: message,
            icon: icon
        )
    }

    /// The tip is route-aware:
    /// - to Shielded (either source): privacy nudge.
    /// - Shielded → Core (L1 withdraw): up-to-10-minute spend delay.
    /// - Shielded → Platform (unshield) / Core → Platform: settles fast.
    /// - Platform → Core: full-balance withdrawal + network processing delay.
    private var icon: DashIconSource {
        switch route {
        case .shieldedToCore, .platformToCore:
            return DashIcon.SystemMessage.timerSmall.source
        default:
            return DashIcon.SystemMessage.shieldSmall.source
        }
    }

    private var title: String {
        switch route {
        case .shieldedToCore:
            return NSLocalizedString("Up to 10 minutes to spend", comment: "")
        case .platformToCore:
            return isFullWithdrawal
                ? NSLocalizedString("Withdraws the entire balance", comment: "Full-balance Platform → Transparent withdrawal")
                : NSLocalizedString("Processing time", comment: "Platform → Transparent withdrawal")
        default:
            return NSLocalizedString("Privacy tip", comment: "")
        }
    }

    private var message: String {
        switch route {
        case .coreToShielded, .platformToShielded:
            return NSLocalizedString(
                "For best privacy, wait at least 2 hours before using these funds.",
                comment: "")
        case .shieldedToCore:
            return NSLocalizedString(
                "After this transfer, it can take up to 10 minutes before you can use your Dash. This delay is part of how your privacy is protected.",
                comment: "")
        case .shieldedToPlatform:
            // Unshield to Platform Payment settles quickly.
            return NSLocalizedString(
                "These funds move to your Platform Payment balance and are ready to spend right away.",
                comment: "")
        case .coreToPlatform:
            return NSLocalizedString(
                "These funds move to your Platform balance and are ready to spend as soon as the transfer completes.",
                comment: "")
        case .platformToCore:
            return isFullWithdrawal
                ? NSLocalizedString(
                    "This withdraws your entire Platform balance in one transfer. The Dash arrives in your Transparent balance once the network processes the withdrawal.",
                    comment: "")
                : NSLocalizedString(
                    "The Dash arrives in your Transparent balance once the network processes the withdrawal.",
                    comment: "")
        }
    }
}

#if DEBUG

private func privacyTipSample(_ route: InternalTransferRoute, isFullWithdrawal: Bool = false) -> some View {
    TransferPrivacyTip(route: route, isFullWithdrawal: isFullWithdrawal)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Core → Shielded") { privacyTipSample(.coreToShielded) }

@available(iOS 17, *)
#Preview("Platform → Shielded") { privacyTipSample(.platformToShielded) }

/// The only route with the clock rather than the shield.
@available(iOS 17, *)
#Preview("Shielded → Core") { privacyTipSample(.shieldedToCore) }

@available(iOS 17, *)
#Preview("Shielded → Platform") { privacyTipSample(.shieldedToPlatform) }

@available(iOS 17, *)
#Preview("Core → Platform") { privacyTipSample(.coreToPlatform) }

/// `.platformToCore` is the one route whose copy changes with the flag.
@available(iOS 17, *)
#Preview("Platform → Core") { privacyTipSample(.platformToCore) }

@available(iOS 17, *)
#Preview("Platform → Core · full") { privacyTipSample(.platformToCore, isFullWithdrawal: true) }

@available(iOS 17, *)
#Preview("Dark") { privacyTipSample(.shieldedToCore).preferredColorScheme(.dark) }

/// The body wraps to several lines already; at accessibility sizes the icon
/// must stay pinned to the first one.
@available(iOS 17, *)
#Preview("Large type") {
    privacyTipSample(.platformToCore, isFullWithdrawal: true)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
