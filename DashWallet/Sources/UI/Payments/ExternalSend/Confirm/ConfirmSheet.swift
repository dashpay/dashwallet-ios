//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DashUIKit
import SwiftUI

/// SCR-06 Confirm and SCR-08 Sending. Draws the ViewModel's state for a send the flow already prepared; Cancel and the
/// close button both call `cancel()`, which does nothing while sending, and the sheet's swipe-down is locked until the
/// outcome.
struct ConfirmSheet: View {
    @ObservedObject var viewModel: ConfirmViewModel

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: String(localized: "Confirm", comment: "External send"),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!viewModel.isDismissLocked),
            showsCloseButton: viewModel.isCancelVisible,
            onClose: viewModel.cancel,
            content: { CappedSheetBody { sheetBody } })
    }

    private var sheetBody: some View {
        VStack(spacing: 16) {
            amount
            card
            warningRows
            buttons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Amount, then the card: From, To, fee, total

    private var amount: some View {
        VStack(spacing: 4) {
            DashUIKit.DashAmount(amount: viewModel.amountDuffs, fontSize: 34, weight: .bold, sign: .none)
            if let fiat = viewModel.amountFiatText {
                Text(fiat)
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        VStack(spacing: 0) {
            DashUIKit.List1View(label: String(localized: "From", comment: "External send"),
                                value: viewModel.fromText)
            recipientRow
            DashUIKit.List1View(label: String(localized: "Network fee", comment: "External send"),
                                value: viewModel.feeRowText)
                .accessibilityElement(children: .combine)
                .accessibilityValue(viewModel.feeAccessibilityValue)
            DashUIKit.List1View(label: String(localized: "Total", comment: "External send"),
                                value: viewModel.totalRowText)
                .accessibilityElement(children: .combine)
                .accessibilityValue(viewModel.totalAccessibilityValue)
        }
        .modifier(DashUIKit.MenuViewModifier())
        .accessibilityElement(children: .contain)
    }

    /// A tap shows the whole recipient, wrapped, and another shortens it again.
    private var recipientRow: some View {
        Button(action: viewModel.toggleRecipient) {
            DashUIKit.List1View(label: String(localized: "To", comment: "External send"), value: viewModel.toText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "To", comment: "External send"))
        .accessibilityValue(viewModel.toAccessibilityValue)
        .accessibilityIdentifier("send_confirm_to")
    }

    // MARK: - Warnings

    private var warningRows: some View {
        ForEach(viewModel.warningItems) { warning in
            DashUIKit.SystemMessageView(
                title: warning.title,
                subtitle: warning.subtitle,
                icon: Self.icon(of: warning.style),
                backgroundColor: warning.style == .caution ? Color.dash.orangeAlpha10 : Color.dash.blueAlpha5)
        }
    }

    private static func icon(of style: ConfirmViewModel.Warning.Style) -> DashUIKit.DashIconSource {
        switch style {
        case .info: return DashIcon.SystemMessage.infoRectSmall.source
        case .delay: return DashIcon.SystemMessage.timerSmall.source
        case .publicExposure: return DashIcon.SystemMessage.public.source
        case .caution: return DashIcon.SystemMessage.warningTriangle.source
        }
    }

    // MARK: - Cancel and Confirm, or Sending

    @ViewBuilder private var buttons: some View {
        if viewModel.isCancelVisible {
            HStack(spacing: 8) {
                DashUIKit.DashButton(
                    text: String(localized: "Cancel", comment: "External send"),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: viewModel.cancel)
                    .accessibilityIdentifier("send_confirm_cancel")
                DashUIKit.DashButton(
                    text: String(localized: "Confirm", comment: "External send"),
                    isEnabled: viewModel.isConfirmEnabled,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: { Task { await viewModel.confirm() } })
                    .accessibilityIdentifier("send_confirm_button")
            }
        } else {
            VStack(spacing: 8) {
                if viewModel.isWaitingForNetwork {
                    DashUIKit.SystemMessageView(
                        title: String(localized: "Waiting for the network", comment: "External send"),
                        subtitle: String(
                            localized: "Confirming this send can take a few minutes. You can close this screen. Don't send it again.",
                            comment: "External send"),
                        icon: DashIcon.SystemMessage.timerSmall.source,
                        backgroundColor: Color.dash.blueAlpha5)
                        .padding(.bottom, 8)
                }
                DashUIKit.DashButton(
                    text: String(localized: "Sending…", comment: "External send"),
                    isLoading: true,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue)
                if viewModel.isWaitingForNetwork {
                    DashUIKit.DashButton(
                        text: String(localized: "Close", comment: "External send"),
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: viewModel.closeWhileWaitingForNetwork)
                        .accessibilityIdentifier("send_confirm_close_while_sending")
                }
            }
        }
    }
}


/// A self-sizing sheet's body: its own height up to what the sheet shows below its header, scrolling past that.
/// `BottomSheet.selfSizing` measures its content at an unconstrained height, so a `ViewThatFits` there always takes
/// the unscrolled body and pushes the buttons out of the sheet; this bounds the body instead.
///
/// The bound starts at DashUIKit's cap. The system can give the sheet less (its own sheet limit below the status bar,
/// a form sheet on iPad, a short window), and the sheet's layout cannot tell, since it is measured unconstrained:
/// the body reads how far it reaches below the sheet's visible area and lowers its bound by that, so the end of its
/// scroll is the bottom of what the holder sees. A new content height starts again from DashUIKit's cap.
///
/// Only an overflow that lasts counts: the sheet first shows at a provisional height (`.medium` before DashUIKit has
/// measured the body) and grows to the body's height a moment later. Lowering the bound to that provisional height
/// would keep the sheet there, with the buttons below its edge.
struct CappedSheetBody<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0
    @State private var fittedHeight: CGFloat?
    @State private var overflowCheck: Task<Void, Never>?

    /// How long an overflow must last before the bound is lowered: longer than the sheet's growth to its measured
    /// height.
    static var overflowSettleDelay: Duration { .milliseconds(600) }

    var body: some View {
        let height = min(contentHeight, fittedHeight ?? Self.maxHeight)
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                contentHeight = $0
                fittedHeight = nil
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height)
        .background(SheetOverflowReader { overflow in
            overflowCheck?.cancel()
            guard overflow > 0.5 else { return }
            overflowCheck = Task { @MainActor in
                try? await Task.sleep(for: Self.overflowSettleDelay)
                guard !Task.isCancelled else { return }
                fittedHeight = max(0, height - overflow)
            }
        })
        .onDisappear { overflowCheck?.cancel() }
    }

    /// DashUIKit's cap (95% of the window, measured without the home-indicator inset), less what `BottomSheet` puts
    /// above the content.
    static var maxHeight: CGFloat {
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.bounds.height
        return (windowHeight ?? UIScreen.main.bounds.height) * 0.95 - headerHeight
    }

    /// `BottomSheet`'s 18-point grabber row and its titled `NavigationBar`, at least 74 points; the bar's buttons are
    /// 44 points and its title one line, so it stays at 74 with any text size.
    static var headerHeight: CGFloat { 18 + 74 }
}

/// Reports how far the view it backs reaches below the visible area of the sheet it is shown in: the presented
/// view's height less its bottom safe-area inset, in the presented view's own coordinates, so the presentation's
/// slide-in does not count. Reported on every layout of the view or of the sheet, zero or less when it fits.
private struct SheetOverflowReader: UIViewRepresentable {
    let onOverflow: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onOverflow = onOverflow
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onOverflow = onOverflow
        view.setNeedsLayout()
    }

    final class ProbeView: UIView {
        var onOverflow: ((CGFloat) -> Void)?
        private var sheetBoundsObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            sheetBoundsObservation = presentedView.map { sheet in
                sheet.observe(\.bounds) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.report() }
                }
            }
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let sheet = presentedView else { return }
            let bottom = convert(bounds, to: sheet).maxY
            let overflow = bottom - (sheet.bounds.height - sheet.safeAreaInsets.bottom)
            // Reported when it is gone too, so a pending check for an overflow the sheet's growth ended is dropped.
            DispatchQueue.main.async { [onOverflow] in onOverflow?(overflow) }
        }

        /// The root view of the presented view controller this view is shown in (not a child controller's, which
        /// reports its parent's presenter as its own).
        private var presentedView: UIView? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController, controller.parent == nil,
                   controller.presentingViewController != nil {
                    return controller.view
                }
                responder = current.next
            }
            return nil
        }
    }
}

#if DEBUG

private let previewAddress = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN"
private let previewIdentityID = "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn"
private let previewShielded =
    "tdash1z4qkl8m3v9x2c7r5n0w6y8t3p1f4g7h2j5k8l0q3w6e9r2t5y8u1i4o7p0a3s6d9f2g5h8j1k4l7z0x3c6v9b2n5m8q1w4e7r0t3y6u9"

@MainActor
private final class PreviewExecutor: ExternalSendExecuting {
    func prepare(route: SendRoute, destination: Destination, amount: UInt64,
                 isMax: Bool, sweepCredits: UInt64?) async throws -> PreparedExternalSend {
        throw ExternalSendError.feeUnavailable
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome { .sent }
    func discard(_ prepared: PreparedExternalSend) {}
}

private struct PreviewBalances: ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64? { nil }
}

/// 1 DASH = 50 units of the local currency.
private struct PreviewConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? { Decimal(duffs) / 100_000_000 * 50 }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { "$\(fiat(forDuffs: duffs) ?? 0)" }
}

private func previewWarning(_ id: Int, _ style: ConfirmViewModel.Warning.Style, _ title: String,
                            _ subtitle: String? = nil) -> ConfirmViewModel.Warning {
    ConfirmViewModel.Warning(id: id, style: style, title: title, subtitle: subtitle)
}

private let publicWarning = previewWarning(
    0, .publicExposure,
    "Sending from Shielded to an address that is not Shielded makes the amount and the destination public.")
private let notInstantWarning = previewWarning(
    0, .info, "When sending from Shielded balance, the transaction is not instant and takes some time")
private let publicToCoreWarning = previewWarning(
    1, .publicExposure, "When sending from Shielded balance to Core the amount and destination becomes public")
private let reserveWarning = previewWarning(0, .caution, SendAmountViewModel.reserveWarningText)
private let unusedPlatformFeeNote = previewWarning(
    0, .info, "Any unused part of the Platform fee goes to the identity.")

@MainActor
private func previewSheet(
    route: SendRoute = .coreToCore, destination: Destination? = nil, recipient: IdentityRecipient? = nil,
    amount: UInt64 = 150_000_000, state: ConfirmViewModel.State = .ready, fee: UInt64? = 1_000,
    warnings: [ConfirmViewModel.Warning] = [], expanded: Bool = false, waitingForNetwork: Bool = false
) -> some View {
    let target = destination ?? Destination(type: .coreAddress, text: previewAddress)
    let vm = ConfirmViewModel(
        request: SendAmountRequest(route: route, destination: target, amount: amount, isMax: false),
        recipient: recipient, executor: PreviewExecutor(), balances: PreviewBalances(),
        converter: PreviewConverter())
    vm.setPreview(state: state, feeDuffs: fee, warnings: warnings, waitingForNetwork: waitingForNetwork)
    if expanded { vm.toggleRecipient() }
    return Color.dash.primaryBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { ConfirmSheet(viewModel: vm) }
}

private let identityDestination = Destination(type: .identityID, text: previewIdentityID)

#Preview("Ready, exact fee") { previewSheet() }

/// "~" before fee and total, "about" for VoiceOver, no note under the fee.
#Preview("Ready, estimated fee") { previewSheet(route: .platformToCore) }

#Preview("Ready, stacked warnings") {
    previewSheet(route: .shieldedToPlatform, destination: Destination(type: .platformAddress, text: previewAddress),
                 warnings: [
                     publicWarning,
                     previewWarning(1, .info, SendWarningText.doubleCheckTitle, SendWarningText.doubleCheckBody)
                 ])
}

/// From "Shielded balance", the two notices under the card, no Processing time.
#Preview("Shielded to Core") {
    previewSheet(route: .shieldedToCore, warnings: [notInstantWarning, publicToCoreWarning])
}

#Preview("Sending") { previewSheet(state: .sending) }

/// The lock's proof is late: the wait is explained and Close leaves the send running.
#Preview("Sending, waiting for the network") {
    previewSheet(route: .coreToShielded, state: .sending, waitingForNetwork: true)
}

#Preview("Sending, waiting for the network, large Dynamic Type") {
    previewSheet(route: .coreToShielded, state: .sending, waitingForNetwork: true)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Identity, reserve warning") {
    previewSheet(route: .identityToCore, warnings: [reserveWarning])
}

#Preview("Recipient, someone else's identity") {
    previewSheet(
        route: .platformToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false))
}

#Preview("Recipient, own identity") {
    previewSheet(
        route: .coreToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "alice", isOwnCurrentIdentity: true),
        warnings: [unusedPlatformFeeNote, previewWarning(1, .info, "This tops up your own Identity credits.")])
}

/// Core -> Identity only: the lock carries Platform's minimum top-up fee, and what Platform does not charge reaches
/// the identity.
#Preview("Core to someone else's identity, unused Platform fee") {
    previewSheet(
        route: .coreToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false),
        fee: 52_750, warnings: [unusedPlatformFeeNote])
}

#Preview("Recipient expanded") { previewSheet(expanded: true) }

#Preview("Payment request, recipient expanded") {
    previewSheet(destination: Destination(type: .coreAddress, text: previewAddress, label: "Merchant",
                                          paymentRequestURL: URL(string: "https://merchant.example/pay/1"),
                                          isVerifiedMerchant: true),
                 expanded: true)
}

#Preview("Identity, recipient expanded") {
    previewSheet(
        route: .platformToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false),
        expanded: true)
}

#Preview("Shielded recipient expanded, large Dynamic Type") {
    previewSheet(route: .shieldedToShielded, destination: Destination(type: .shieldedAddress, text: previewShielded),
                 expanded: true)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Shielded recipient collapsed, large Dynamic Type") {
    previewSheet(route: .shieldedToShielded, destination: Destination(type: .shieldedAddress, text: previewShielded))
        .dynamicTypeSize(.accessibility3)
}

#Preview("Long text, large Dynamic Type") {
    previewSheet(
        route: .shieldedToCore, amount: 123_456_789_012_345, fee: 12_345_678,
        warnings: [notInstantWarning, publicToCoreWarning]
    )
    .dynamicTypeSize(.accessibility3)
}

#endif
