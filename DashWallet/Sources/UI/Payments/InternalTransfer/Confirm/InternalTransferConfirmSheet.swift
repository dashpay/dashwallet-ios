//
//  InternalTransferConfirmSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit
import SwiftDashSDK

/// Confirmation half-sheet shown when the user taps `Continue` on the
/// Internal transfer screen.
///
/// It confirms and then gets out of the way: Confirm authenticates, hands the
/// transfer to `InternalTransferRunner`, which outlives this sheet, and the
/// host closes it. Progress, success and failure are no longer shown here —
/// waiting on a modal for a transfer that can take minutes was the thing being
/// removed. The runner announces the outcome wherever the user ended up.
///
/// The PIN prompt is the one thing that is NOT deferred: it is raised and
/// answered over this sheet, before the dismissal. Confirm is what the user
/// authorized, so the prompt belongs to the screen they tapped it on, not to
/// whatever they land on afterwards.
///
/// Drawing only: what the summary says and which privacy note applies are
/// `InternalTransferConfirmViewModel`'s.
struct InternalTransferConfirmSheet: View {

    @StateObject private var viewModel: InternalTransferConfirmViewModel

    /// Confirm is awaiting the PIN prompt. The prompt covers this sheet while
    /// it is up, so this is not about showing progress — it is what stops a
    /// second tap from queueing a second gate behind the first.
    @State private var isSubmitting = false

    var onCancel: () -> Void
    /// Called once the transfer has been authorized and handed off — the host
    /// closes the sheet and returns the user to the history. NOT a completion
    /// callback: the transfer is still running when this fires.
    var onSubmitted: () -> Void
    var onPlatformShieldCapacityChanged: (UInt64?, Bool) -> Void

    init(
        route: InternalTransferRoute?,
        dashDuffs: Int64,
        amountDuffsUnsigned: UInt64,
        creditsAmount: UInt64,
        fiatText: String,
        withdrawalFeeCredits: UInt64? = nil,
        isFullPlatformWithdrawal: Bool = false,
        isFullShieldedSweep: Bool = false,
        platformShieldAmountWasMax: Bool = false,
        identityTopUp: IdentityTopUpTransfer? = nil,
        identityWithdrawal: IdentityWithdrawalTransfer? = nil,
        onCancel: @escaping () -> Void,
        onSubmitted: @escaping () -> Void,
        onPlatformShieldCapacityChanged: @escaping (UInt64?, Bool) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: InternalTransferConfirmViewModel(
            route: route,
            identityTopUp: identityTopUp,
            identityWithdrawal: identityWithdrawal,
            dashDuffs: dashDuffs,
            amountDuffsUnsigned: amountDuffsUnsigned,
            creditsAmount: creditsAmount,
            fiatText: fiatText,
            withdrawalFeeCredits: withdrawalFeeCredits,
            isFullPlatformWithdrawal: isFullPlatformWithdrawal,
            isFullShieldedSweep: isFullShieldedSweep,
            platformShieldAmountWasMax: platformShieldAmountWasMax))
        self.onCancel = onCancel
        self.onSubmitted = onSubmitted
        self.onPlatformShieldCapacityChanged = onPlatformShieldCapacityChanged
    }

    var body: some View {
        // Grabber, title and background come from the design system rather
        // than being drawn here. `fillsHeight: true` because the host asks for
        // `selfSizing` measures the content instead of taking a detent: the
        // summary card is four fixed rows and the privacy note is a couple of
        // lines, so a `.large` sheet was mostly empty space. Nothing below may
        // grow greedily — no `Spacer`, no `maxHeight: .infinity` — or the
        // measurement expands to whatever the sheet was offered.
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Confirm", comment: "Payments"),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 0) {

                VStack(alignment: .leading, spacing: 20) {
                    // The design system's amount pair: the Dash figure with
                    // its logo, the converted value under it.
                    DashUIKit.SwapAmountView(
                        amount: viewModel.dashAmountText,
                        secondaryText: viewModel.fiatText,
                        showDashLogo: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                    TransferSummaryCard(summary: viewModel.summary)

                    privacyTip
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                HStack(spacing: 20) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Cancel", comment: "Payments"),
                        isEnabled: !isSubmitting,
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: onCancel
                    )

                    DashUIKit.DashButton(
                        text: NSLocalizedString("Confirm", comment: "Payments"),
                        isLoading: isSubmitting,
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue,
                        action: submit
                    )
                }
                .padding(20)
            }
        }
        .onChange(of: viewModel.platformShieldCapacityChange) { _, change in
            guard let change else { return }
            onPlatformShieldCapacityChanged(
                change.maxShieldableCredits,
                change.submittedAmountWasMax)
        }
    }

    /// Authorize, then leave — in that order.
    ///
    /// The sheet stays up for the PIN prompt and closes only once the gate has
    /// resolved. Closing first (which is what the hand-off originally did) put
    /// the prompt on the home screen the user had just been dropped onto,
    /// asking them to authorize something no longer on screen. Backing out of
    /// the prompt is not an error: the summary is simply still there.
    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            let handedOff = await viewModel.confirm()
            isSubmitting = false
            if handedOff { onSubmitted() }
        }
    }

    @ViewBuilder
    private var privacyTip: some View {
        if let context = viewModel.privacyTipContext {
            TransferPrivacyTip(context: context)
        }
    }
}

#if DEBUG

/// The sheet owns its coordinator and `phase` is `private(set)`, so previews
/// can only reach the idle summary. The in-flight, success and failure bodies
/// are previewed through `ShieldedTransferStepList` and
/// `ShieldedSubmittedUnconfirmedView` below.
///
/// Network-fee and total rows ask the SDK to price the route; without a wallet
/// those return `nil` and the rows render "—". `.coreToPlatform` prices from a
/// constant, so it is the route to use when the fee row itself matters.
private func confirmSheetSample(
    route: InternalTransferRoute?,
    dash: Decimal = 0.5,
    withdrawalFeeCredits: UInt64? = nil,
    isFullPlatformWithdrawal: Bool = false,
    isFullShieldedSweep: Bool = false,
    identityTopUp: IdentityTopUpTransfer? = nil,
    identityWithdrawal: IdentityWithdrawalTransfer? = nil
) -> some View {
    let duffs = Int64(truncating: NSDecimalNumber(decimal: dash * 100_000_000))
    return InternalTransferConfirmSheet(
        route: route,
        dashDuffs: duffs,
        amountDuffsUnsigned: UInt64(duffs),
        creditsAmount: UInt64(duffs) * 1000,
        fiatText: "$32.75",
        withdrawalFeeCredits: withdrawalFeeCredits,
        isFullPlatformWithdrawal: isFullPlatformWithdrawal,
        isFullShieldedSweep: isFullShieldedSweep,
        platformShieldAmountWasMax: false,
        identityTopUp: identityTopUp,
        identityWithdrawal: identityWithdrawal,
        onCancel: {},
        onSubmitted: {},
        onPlatformShieldCapacityChanged: { _, _ in })
}

/// Identity destination funded from `source`. Without a wallet the shielded
/// funding's fee row renders "—"; the transparent-side sources price from
/// the observed transition-fee constant, so their fee row shows a number.
private func identityConfirmSheetSample(source: ChainNetwork) -> some View {
    confirmSheetSample(
        route: nil,
        identityTopUp: IdentityTopUpTransfer(
            identityId: Data(repeating: 0x07, count: 32),
            source: source))
}

@available(iOS 17, *)
#Preview("Core → Platform") {
    confirmSheetSample(route: .coreToPlatform)
}

@available(iOS 17, *)
#Preview("Core → Shielded") {
    confirmSheetSample(route: .coreToShielded)
}

@available(iOS 17, *)
#Preview("Shielded → Core · sweep") {
    confirmSheetSample(route: .shieldedToCore, isFullShieldedSweep: true)
}

/// Full-balance withdrawal: the fee is already netted out of the payout, and
/// the preflight fee is the only one the sheet can show.
@available(iOS 17, *)
#Preview("Platform → Core · full") {
    confirmSheetSample(
        route: .platformToCore,
        withdrawalFeeCredits: 1_240_000,
        isFullPlatformWithdrawal: true)
}

/// Identity destination from the Transparent balance — the linkability
/// warning replaces the route privacy tip and To reads "Identity".
@available(iOS 17, *)
#Preview("→ Identity · from Transparent") {
    identityConfirmSheetSample(source: .core)
}

@available(iOS 17, *)
#Preview("→ Identity · from Shielded") {
    identityConfirmSheetSample(source: .shielded)
}

private func withdrawalConfirmSheetSample(target: IdentityWithdrawalTarget) -> some View {
    confirmSheetSample(
        route: nil,
        identityWithdrawal: IdentityWithdrawalTransfer(
            identityId: Data(repeating: 0x07, count: 32),
            target: target))
}

/// Identity source: From reads "Identity" and the fee row is the em dash —
/// neither withdrawal transition has an SDK fee estimate to print.
@available(iOS 17, *)
#Preview("Identity → · Transparent") {
    withdrawalConfirmSheetSample(target: .transparent)
}

@available(iOS 17, *)
#Preview("Identity → · Platform") {
    withdrawalConfirmSheetSample(target: .platform)
}

@available(iOS 17, *)
#Preview("Dark") {
    confirmSheetSample(route: .coreToPlatform)
        .preferredColorScheme(.dark)
}

/// Presented the way the screen presents it — verifies the drag handle and the
/// `.large` detent, which the bare-content previews above can't show.
@available(iOS 17, *)
#Preview("As a sheet") {
    Color.dash.primaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            confirmSheetSample(route: .coreToPlatform)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
}

#endif
