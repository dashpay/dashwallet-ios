//
//  TransferPrivacyTip.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// The note under the confirm sheet's summary: what this particular transfer
/// means for privacy, or how long the money takes to become spendable.
///
/// Context in, copy out — it reads nothing else, which is why it is a view of
/// its own rather than eighty lines inside a sheet that also runs a transfer.
/// Each of the balance routes and the identity funding sources can be looked
/// at on its own in the canvas.
///
/// The drawing is `DashUIKit.SystemMessageView`; what stays here is the mapping
/// from context to words, which is the app's and not the design system's.
struct TransferPrivacyTip: View {
    /// What the confirm sheet is confirming.
    enum Context {
        /// A balance-to-balance route. `isFullWithdrawal` matters only for
        /// `.platformToCore`: the amount is the whole balance, which the
        /// copy says out loud.
        case route(InternalTransferRoute, isFullWithdrawal: Bool)
        /// An identity top-up funded from `from` — the copy carries the
        /// linkability consequence of that source, same as the profile
        /// sheet's top-up picker.
        case identityTopUp(from: ChainNetwork)
        /// Credits leaving the identity for `to`. What the copy has to say
        /// is the settling time, which differs sharply between the two
        /// targets.
        case identityWithdrawal(to: IdentityWithdrawalTarget)
    }

    let context: Context

    /// Dismissed for this presentation only. The sheet builds a fresh tip every
    /// time it opens, so closing it is "not now" rather than "never again" —
    /// nothing here writes a preference, and a tip that stayed gone would need
    /// one.
    @State private var isVisible = true

    @ViewBuilder
    var body: some View {
        if isVisible {
            DashUIKit.SystemMessageView(
                title: title,
                subtitle: message,
                icon: icon,
                backgroundColor: Color.dash.blueAlpha5,
                onClose: { isVisible = false }
            )
        }
    }

    /// The tip is context-aware:
    /// - to Shielded (either source) and every identity top-up: privacy nudge.
    /// - Shielded → Core (L1 withdraw): up-to-10-minute spend delay.
    /// - Shielded → Platform (unshield) / Core → Platform: settles fast.
    /// - Platform → Core: full-balance withdrawal + network processing delay.
    private var icon: DashIconSource {
        switch context {
        case .route(.shieldedToCore, _), .route(.platformToCore, _),
             .identityWithdrawal(.transparent):
            return DashIcon.SystemMessage.timerSmall.source
        case .route(.shieldedToPlatform, _), .route(.coreToPlatform, _),
             .identityWithdrawal(.platform):
            // Their message is about when the funds are spendable, so they
            // take the timing glyph rather than the privacy shield.
            return DashIcon.SystemMessage.timerSmall.source
        default:
            return DashIcon.SystemMessage.shieldSmall.source
        }
    }

    private var title: String {
        switch context {
        case .identityWithdrawal(.transparent):
            return NSLocalizedString("Processing time", comment: "Platform → Transparent withdrawal")
        case .identityWithdrawal(.platform):
            return NSLocalizedString("Ready right away", comment: "Identity → Platform credit transfer")
        case .route(.shieldedToCore, _):
            return NSLocalizedString("Up to 10 minutes to spend", comment: "")
        case .route(.platformToCore, let isFullWithdrawal):
            return isFullWithdrawal
                ? NSLocalizedString("Withdraws the entire balance", comment: "Full-balance Platform → Transparent withdrawal")
                : NSLocalizedString("Processing time", comment: "Platform → Transparent withdrawal")
        case .route(.shieldedToPlatform, _), .route(.coreToPlatform, _):
            // Both messages say the funds are spendable immediately — the same
            // statement the identity → Platform transfer already titles this
            // way. "Privacy tip" over a sentence about timing reads as a
            // heading for a different card.
            return NSLocalizedString("Ready right away", comment: "Identity → Platform credit transfer")
        default:
            return NSLocalizedString("Privacy tip", comment: "")
        }
    }

    private var message: String {
        switch context {
        case .route(let route, let isFullWithdrawal):
            return Self.routeMessage(route, isFullWithdrawal: isFullWithdrawal)
        case .identityWithdrawal(let target):
            switch target {
            case .transparent:
                // Same asynchronous asset-unlock payout the Platform → Core
                // withdrawal describes, so it borrows that route's wording.
                return NSLocalizedString(
                    "The Dash arrives in your Transparent balance once the network processes the withdrawal.",
                    comment: "")
            case .platform:
                return NSLocalizedString(
                    "These credits move to your Platform balance and are ready to spend right away.",
                    comment: "Identity → Platform credit transfer")
            }
        case .identityTopUp(let source):
            // Same wording (and localization keys) as the profile sheet's
            // top-up source picker — both describe the same funding paths.
            switch source {
            case .shielded:
                return NSLocalizedString(
                    "Recommended: a two-step transfer through your own Platform address keeps your identity unlinked from your transparent coins.",
                    comment: "Identity top-up sheet — shielded source note")
            case .core, .platform:
                return NSLocalizedString(
                    "Funding from a transparent balance publicly links those coins to your identity on the Dash chain. For privacy, pay from your Shielded balance.",
                    comment: "Identity top-up sheet — linkability warning for transparent-side sources")
            }
        }
    }

    private static func routeMessage(_ route: InternalTransferRoute, isFullWithdrawal: Bool) -> String {
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

private func privacyTipSample(_ context: TransferPrivacyTip.Context) -> some View {
    TransferPrivacyTip(context: context)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

private func privacyTipSample(_ route: InternalTransferRoute, isFullWithdrawal: Bool = false) -> some View {
    privacyTipSample(.route(route, isFullWithdrawal: isFullWithdrawal))
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

/// Identity top-up from the privacy-recommended source.
@available(iOS 17, *)
#Preview("→ Identity · from Shielded") { privacyTipSample(.identityTopUp(from: .shielded)) }

/// Transparent-side funding carries the linkability warning.
@available(iOS 17, *)
#Preview("→ Identity · from Transparent") { privacyTipSample(.identityTopUp(from: .core)) }

/// Out of the identity: the transparent payout waits on the network, so it
/// is the clock rather than the shield.
@available(iOS 17, *)
#Preview("Identity → · Transparent") { privacyTipSample(.identityWithdrawal(to: .transparent)) }

@available(iOS 17, *)
#Preview("Identity → · Platform") { privacyTipSample(.identityWithdrawal(to: .platform)) }

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
