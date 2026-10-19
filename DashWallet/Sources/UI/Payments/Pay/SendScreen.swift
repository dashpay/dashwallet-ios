//
//  SendScreen.swift
//  DashWallet
//
//  External-send flow, split across two steps. Step one (`SendScreen`) is
//  address only: the recipient address (typed / pasted / scanned) decides the
//  destination type (Transparent L1 / Platform / Shielded); Continue advances
//  to step two. Step two (`ExternalSendAmountScreen`) is the From picker plus
//  the amount keypad — Core → Core continues into the classic payment
//  processor (real fee math + its own confirm); every other route confirms in
//  `SendConfirmSheet` and executes via `ShieldedTransferCoordinator`.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Step 1: address

struct SendScreen: View {
    @ObservedObject var viewModel: SendViewModel
    var onClose: () -> Void
    var onScanQR: () -> Void
    /// The entered address is valid → advance to the amount step. The host
    /// pushes `ExternalSendAmountScreen` onto the same navigation stack.
    var onContinue: () -> Void
    /// False when embedded under a host that renders its own chrome
    /// (the balance-row send sheet) — hides the X + title header.
    var showsHeader: Bool = true

    /// Set when the screen was pushed: the header's leading slot becomes a
    /// back button instead of a close one, and the host hides the UIKit bar.
    var onBack: (() -> Void)? = nil

    @FocusState private var addressFieldFocused: Bool
    @State private var isEditingAddress = false
    /// Identifies this instance's clipboard-monitoring registration. During a
    /// tab change two `SendScreen`s are alive at once, so the outgoing one's
    /// `onDisappear` must withdraw only its own.
    @State private var clipboardMonitorToken = UUID()

    /// The address is "locked" (shown as a truncated card) once a valid
    /// destination is decoded and focus has left the field; tapping it reopens
    /// the editable field.
    private var isAddressLocked: Bool {
        viewModel.destination != nil && !isEditingAddress && !addressFieldFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                // No padding of its own: `NavigationBar` already insets its
                // leading/trailing slots by 20 and stands 64 tall.
                header
            }

            ScrollView {
                VStack(spacing: 14) {
                    addressField
                        .padding(.top, 12)

                    if let suggestion = viewModel.clipboardSuggestion,
                       suggestion.address != viewModel.trimmedAddress {
                        clipboardChip(for: suggestion)
                    }

                    scanRow
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                stretch: true,
                isEnabled: viewModel.canAdvanceToAmount,
                action: {
                    addressFieldFocused = false
                    onContinue()
                })
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .task {
            // A pasteboard read can block on the system permission dialog.
            // Let the address form's entrance animation finish first. This
            // view can still be on its way out when the sleep ends — its
            // removal transition outlasts the delay — which is why the read
            // itself is gated on the host's `isClipboardReadAllowed`.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.setClipboardMonitoring(true, token: clipboardMonitorToken)
        }
        .onDisappear { viewModel.setClipboardMonitoring(false, token: clipboardMonitorToken) }
    }

    // MARK: - Header

    /// Back when the screen was pushed, close when it is the root of its own
    /// presentation. Both come from the design system's bar rather than the
    /// UIKit one, so the glyph and its ring are the `navigationbar-*` assets.
    private var header: some View {
        DashUIKit.NavigationBar(
            leading: {
                if let onBack {
                    DashUIKit.NavigationBarElement.back.button(action: onBack)
                } else {
                    DashUIKit.NavigationBarElement.close.button(action: onClose)
                }
            },
            central: {
                Text(NSLocalizedString("Send", comment: ""))
                    .dashFont(.subheadMedium)
                    .foregroundColor(Color.dash.primaryText)
            })
    }

    // MARK: - Address

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("Address", comment: ""))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                Spacer()
                if let destination = viewModel.destination {
                    destinationBadge(destination)
                }
            }
            if isAddressLocked {
                lockedAddressCard
            } else {
                TextField(
                    NSLocalizedString("Dash address", comment: "Send screen address placeholder"),
                    text: $viewModel.addressText,
                    axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .padding(12)
                    .background(Color.dash.secondaryBackground)
                    .cornerRadius(10)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("send_address_field")
                    .focused($addressFieldFocused)
                    .onAppear {
                        // Rendered after tapping the locked card → put the
                        // cursor straight back into the field.
                        if isEditingAddress {
                            addressFieldFocused = true
                        }
                    }
                    .onChange(of: addressFieldFocused) { _, focused in
                        // Focus left the field → re-lock (when valid).
                        if !focused {
                            isEditingAddress = false
                        }
                    }
                    .onChange(of: viewModel.destination) { _, destination in
                        // The address just became valid (a paste, or the
                        // final typed character) → lock in right away.
                        // Software-keyboard-less setups (simulator with a
                        // hardware keyboard) never drop focus on their own,
                        // so don't wait for that.
                        if destination != nil {
                            addressFieldFocused = false
                            isEditingAddress = false
                        }
                    }
            }

            if viewModel.showsInvalidAddress {
                Text(NSLocalizedString("This is not a valid Dash address for this network", comment: "Send screen"))
                    .font(.caption)
                    .foregroundColor(.red)
            } else if viewModel.pinnedSourceMismatch {
                Text(String(
                    format: NSLocalizedString("This address can't be paid from your %@ balance", comment: "Send sheet source/destination mismatch"),
                    viewModel.pinnedSourceTitle))
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
    }

    /// The locked-in address: middle-truncated single line + pencil.
    /// Tapping reopens the editable field with the cursor in place.
    private var lockedAddressCard: some View {
        Button(action: { isEditingAddress = true }) {
            HStack(spacing: 8) {
                Text(truncateMiddle(viewModel.trimmedAddress, visible: 10))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.dash.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("send_address_locked")
    }

    private func destinationBadge(_ destination: SendViewModel.DestinationKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: destinationIconName(destination))
                .font(.system(size: 10, weight: .semibold))
            Text(destinationTitle(destination))
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.dash.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.dash.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private func destinationIconName(_ destination: SendViewModel.DestinationKind) -> String {
        switch destination {
        case .core: return "d.circle.fill"
        case .platform: return "creditcard.fill"
        case .shielded: return "shield.fill"
        }
    }

    private func destinationTitle(_ destination: SendViewModel.DestinationKind) -> String {
        switch destination {
        case .core: return NSLocalizedString("Transparent address", comment: "Send screen destination type")
        case .platform: return NSLocalizedString("Platform address", comment: "Send screen destination type")
        case .shielded: return NSLocalizedString("Shielded address", comment: "Send screen destination type")
        }
    }

    private func clipboardChip(for suggestion: SendViewModel.ClipboardSuggestion) -> some View {
        Button(action: { viewModel.useClipboardSuggestion() }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Send to copied address", comment: ""))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    Text(truncateMiddle(suggestion.address))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(destinationTitle(suggestion.kind))
                    .font(.caption2)
                    .foregroundColor(Color.dash.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.dash.gray300.opacity(0.3))
                    .cornerRadius(8)
            }
            .padding(12)
            .background(Color.dash.blue.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }

    private var scanRow: some View {
        Button(action: onScanQR) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode.viewfinder")
                Text(NSLocalizedString("Scan QR", comment: ""))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.dash.blue.opacity(0.12))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Step 2: amount

/// The amount step for the split external-send flow. The address is already
/// chosen (locked, read-only) — this screen carries the From picker, the
/// sync gate, and the amount keypad, plus the balance/affordability
/// validations. Continue routes exactly as the old single-screen form did:
/// Core → Core into the L1 payment processor, everything else into
/// `SendConfirmSheet`.
struct SendSourceScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the address step.
    var onBack: () -> Void
    /// A valid source is chosen → advance to the amount step.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SendStepHeader(onBack: onBack)

            ScrollView {
                VStack(spacing: 14) {
                    SendAddressSummary(viewModel: viewModel, onEdit: onBack)
                        .padding(.top, 12)

                    sourceCards

                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                stretch: true,
                isEnabled: viewModel.route != nil && !viewModel.isBlockedBySync,
                action: onContinue)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - From picker

    @ViewBuilder
    private var sourceCards: some View {
        if let pinned = viewModel.pinnedSource {
            // Balance-row send sheet: the source is the tapped balance,
            // rendered as a fixed card (no radio, not tappable).
            sourceRow(pinned, showsRadio: false)
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.validSources, id: \.self) { network in
                    sourceRow(network)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func sourceRow(_ network: ChainNetwork, showsRadio: Bool = true) -> some View {
        let balance: String
        switch network {
        case .core: balance = viewModel.coreBalanceFormatted
        case .platform: balance = viewModel.platformCreditsFormatted
        case .shielded: balance = viewModel.shieldedBalanceFormatted
        }
        return TransferSourceRow(
            iconSystemName: sourceIconName(network),
            caption: NSLocalizedString("From", comment: ""),
            title: sourceTitle(network),
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: viewModel.source == network,
            showsRadio: showsRadio,
            action: { viewModel.source = network })
    }
}

// MARK: - Step 3: amount

/// The final step of the split external-send flow: the recipient and source
/// are already chosen (both shown read-only), leaving only the amount keypad
/// and the balance/affordability validation. Continue routes exactly as the
/// old single-screen form did — Core → Core into the L1 payment processor,
/// everything else into `SendConfirmSheet`.
///
/// Also the amount step for a DashPay contact, which the picker and the
/// contact profile open directly: same screen, same view model, with the
/// recipient rendered as a contact. Send asks for the PIN and has the view
/// model sign the payment (`prepareContactReview`), then opens
/// `ConfirmContactSendSheet` on it with the exact fee and total; once the
/// review is sent and closed, `onContinueContact` has the host run
/// `sendToContact`, which broadcasts that signed payment.
struct ExternalSendAmountScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the step that chose the recipient — the source step for an
    /// address, the contact picker for a contact.
    var onBack: () -> Void
    /// Core → Core: hand (address, amount in duffs) to the hosting
    /// controller, which routes through the L1 payment processor.
    var onContinueCore: (String, UInt64) -> Void
    /// Contact route: the review was sent and has closed. The host runs
    /// `viewModel.sendToContact()` and shows the outcome.
    var onContinueContact: () -> Void
    /// A non-core route finished successfully (confirm sheet's Done).
    var onSendCompleted: () -> Void

    @State private var showConfirm = false
    /// Set by the confirm sheet's Done so `onDismiss` can tell a finished send
    /// from a cancelled one — both close the sheet the same way.
    @State private var didCompleteSend = false
    /// Pre-send review for the DashPay contact route.
    @State private var showContactConfirm = false
    /// The review the sheet is showing (`SendViewModel.contactReviewID`),
    /// set when it appears. Its `onDismiss` closes that review only, so a
    /// late dismissal never closes the next one; and the amount step's Send
    /// is ignored while the current review is on screen.
    @State private var shownContactReviewID: Int?

    var body: some View {
        VStack(spacing: 0) {
            #if DASHPAY
            if let contact = viewModel.contactRecipient {
                DashUIKit.NavigationBar(leading: {
                    // Leaving mid-broadcast would hide the outcome — the
                    // success, or the "don't send it again" notice.
                    DashUIKit.NavigationBarElement.back.button(action: {
                        if !isContactSendInFlight { onBack() }
                    })
                })
                SendContactIntro(
                    contact: contact,
                    balanceDuffs: viewModel.coreToCoreSpendableDuffs)
                    .padding(.horizontal, 20)
            } else {
                SendStepHeader(onBack: onBack)
            }
            #else
            SendStepHeader(onBack: onBack)
            #endif

            ScrollView {
                VStack(spacing: 14) {
                    // The contact route names its recipient in the intro
                    // above; only the address route repeats it as a card,
                    // where tapping it is also the way back to editing.
                    if !isContactSend {
                        SendAddressSummary(viewModel: viewModel, onEdit: onBack)
                            .padding(.top, 12)
                    }

                    if !isContactSend {
                        fromSummary
                    }

                    amountRow
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    if let message = viewModel.amountValidationMessage {
                        TransferAmountValidationNote(message: message)
                            .padding(.horizontal, 20)
                    }

                    // The address flow meets this gate on the source step,
                    // which won't advance while it is up — but a restored
                    // wallet can start resyncing while this screen is open, and
                    // the contact flow never passes through that step at all.
                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        // `onDismiss`, not the sheet's own completion closure: leaving the flow
        // pops the steps under this sheet, and doing that while it is still
        // presented tears down the presenter mid-dismissal. A cancel dismisses
        // the same way and must not unwind, so the outcome is carried across.
        #if DASHPAY
        // A sheet or the PIN prompt over this step does not count as leaving
        // it; a pop, a dismissal or a tab switch does.
        .onAppear { viewModel.contactAmountStepDidAppear() }
        .onDisappear { viewModel.contactAmountStepDidDisappear() }
        // The broadcast starts from `onDismiss`, once the review is gone, so
        // the host's outcome screen never presents over a sheet that is still
        // on its way out. Any other close abandons the signed payment.
        .sheet(isPresented: $showContactConfirm, onDismiss: {
            let closedReviewID = shownContactReviewID
            shownContactReviewID = nil
            if viewModel.isSendingToContact {
                onContinueContact()
            } else {
                // A sheet that never appeared was replaced by the next
                // review before it showed; that review is not this one's to
                // close, and the next prepare already released its payment.
                if let closedReviewID { viewModel.cancelContactReview(id: closedReviewID) }
            }
        }) {
            if let contact = viewModel.contactRecipient,
               let duffs = viewModel.contactReviewDuffs,
               let feeDuffs = viewModel.contactReviewFeeDuffs,
               let totalDuffs = viewModel.contactReviewTotalDuffs {
                ConfirmContactSendSheet(
                    contact: contact,
                    amountDuffs: duffs,
                    feeDuffs: feeDuffs,
                    totalDuffs: totalDuffs,
                    fiatText: viewModel.contactReviewFiatText ?? "",
                    onCancel: { showContactConfirm = false },
                    onSend: {
                        viewModel.confirmContactReview()
                        showContactConfirm = false
                    })
                    .onAppear { shownContactReviewID = viewModel.contactReviewID }
                // No detent here: the sheet is `BottomSheet.selfSizing`, which
                // sets its own from the measured content.
            }
        }
        #endif
        .sheet(isPresented: $showConfirm, onDismiss: {
            guard didCompleteSend else { return }
            didCompleteSend = false
            onSendCompleted()
        }) {
            if let route = viewModel.route, route != .coreToCore {
                SendConfirmSheet(
                    route: route,
                    destinationAddress: viewModel.trimmedAddress,
                    destinationRaw43: shieldedRecipientRaw43,
                    dashDuffs: viewModel.dashDuffs,
                    creditsAmount: viewModel.creditsPreview,
                    fiatText: viewModel.fiatAmountString,
                    withdrawalFeeCredits: viewModel.withdrawalPreflight?.estimatedFee,
                    isFullPlatformWithdrawal: viewModel.isFullPlatformWithdrawal,
                    isFullShieldedSweep: viewModel.isFullShieldedSweep,
                    onCancel: { showConfirm = false },
                    onCompleted: {
                        didCompleteSend = true
                        showConfirm = false
                    })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private var shieldedRecipientRaw43: Data? {
        if case .shielded(let raw43) = viewModel.destination { return raw43 }
        return nil
    }

    // MARK: - Amount

    private var amountRow: some View {
        EnterAmountView(
            primaryAmount: dashAmountText,
            secondaryAmount: fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(viewModel.fiatCurrencyCode),
            isPrimarySelected: isDashInputSelected,
            currencyCodes: amountCurrencyCodes,
            selectedCurrencyCode: selectedAmountCurrencyCode,
            onMax: { viewModel.fillMaxFromWallet() },
            onSwap: toggleAmountUnit,
            onCurrencyTap: toggleAmountUnit,
            onSelectInputType: selectAmountCurrency
        )
    }

    // MARK: - Keyboard

    private var keyboardSection: some View {
        HardwareNumericKeyboardView(
            value: keypadBinding,
            showDecimalSeparator: true,
            // A contact payment's review, opened by this tap, is the last
            // step before the broadcast; every other route continues to a
            // flow of its own (the L1 payment processor or `SendConfirmSheet`).
            actionButtonText: isContactSend
                ? NSLocalizedString("Send", comment: "")
                : NSLocalizedString("Continue", comment: ""),
            actionEnabled: viewModel.canContinue,
            inProgress: isContactSendInFlight,
            actionHandler: continueAction
        )
    }

    private func continueAction() {
        if isContactSend {
            // Never straight to the broadcast: this signs the payment (after
            // the PIN) and opens the review on its exact fee and total; only
            // the review's Send broadcasts it.
            #if DASHPAY
            if let shown = shownContactReviewID, shown == viewModel.contactReviewID { return }
            // A review that was asked for and never appeared, or is still on
            // its way in, left this set; clear it so the next one presents.
            showContactConfirm = false
            Task { @MainActor in
                if await viewModel.prepareContactReview() {
                    showContactConfirm = true
                }
            }
            #endif
            return
        }
        guard let route = viewModel.route else { return }
        if route == .coreToCore {
            onContinueCore(viewModel.trimmedAddress, viewModel.dashDuffsUnsigned)
        } else {
            showConfirm = true
        }
    }

    /// True on the DashPay contact route. Always false in the dashwallet
    /// target, which has no contacts — so the contact branches below are
    /// compiled out of every path there.
    private var isContactSend: Bool {
        #if DASHPAY
        return viewModel.contactRecipient != nil
        #else
        return false
        #endif
    }

    /// From the amount step's Send to the review, and from the review's Send
    /// on — `isSendingToContact` covers the review's exit as well as the
    /// broadcast.
    private var isContactSendInFlight: Bool {
        #if DASHPAY
        return viewModel.isContactPaymentInFlight
        #else
        return false
        #endif
    }

    /// The source picked on the previous step, read-only. Tapping goes back —
    /// except on the contact route, where the transparent balance is the only
    /// possible source and there is no From step behind this screen, so the
    /// card is a fact rather than a way back.
    private var fromSummary: some View {
        Button(action: onBack) {
            HStack(spacing: 10) {
                Image(systemName: sourceIconName(viewModel.source))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dashBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("From", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(sourceTitle(viewModel.source))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primaryText)
                }
                Spacer()
                if !isContactSend {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.secondaryBackground)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isContactSend)
        .padding(.horizontal, 20)
    }

    // MARK: - Amount helpers

    private var isDashInputSelected: Bool {
        viewModel.unit == .dash
    }

    private var dashAmountText: String {
        switch viewModel.unit {
        case .dash:
            return keypadBinding.wrappedValue
        case .fiat:
            guard viewModel.parsedDashAmount > 0 else { return "" }
            return InternalTransferViewModel.formatTyped(
                viewModel.parsedDashAmount,
                fractionDigits: 8)
        }
    }

    private var fiatAmountText: String {
        switch viewModel.unit {
        case .dash:
            guard viewModel.parsedDashAmount > 0,
                  let fiatAmount = try? CurrencyExchanger.shared.convertDash(
                    amount: viewModel.parsedDashAmount,
                    to: viewModel.fiatCurrencyCode)
            else { return "" }
            return InternalTransferViewModel.formatTyped(
                fiatAmount,
                fractionDigits: 2)
        case .fiat:
            return keypadBinding.wrappedValue
        }
    }

    private var amountCurrencyCodes: [String] {
        ["DASH", viewModel.fiatCurrencyCode]
    }

    private var selectedAmountCurrencyCode: String {
        isDashInputSelected ? "DASH" : viewModel.fiatCurrencyCode
    }

    private func toggleAmountUnit() {
        viewModel.unit = isDashInputSelected ? .fiat : .dash
    }

    private func selectAmountCurrency(_ currencyCode: String) {
        viewModel.unit =
            currencyCode.caseInsensitiveCompare("DASH") == .orderedSame
            ? .dash
            : .fiat
    }

    private var keypadBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText == "0" ? "" : viewModel.amountText },
            set: { newValue in
                if newValue.isEmpty {
                    viewModel.amountText = "0"
                // Shorter text always passes: a unit switch can leave more decimals than
                // the new unit allows, and refusing backspace would lock the field.
                } else if newValue.count < viewModel.amountText.count
                    || InternalTransferViewModel.typedTextFitsPrecision(newValue, unit: viewModel.unit) {
                    viewModel.amountText = newValue
                }
            })
    }
}

// MARK: - Shared step chrome

/// Back + "Send" title, shared by the source and amount steps.
private struct SendStepHeader: View {
    var onBack: () -> Void

    var body: some View {
        DashUIKit.NavigationBar(
            leading: { DashUIKit.NavigationBarElement.back.button(action: onBack) },
            central: {
                Text(NSLocalizedString("Send", comment: ""))
                    .dashFont(.subheadMedium)
                    .foregroundColor(Color.dash.primaryText)
            })
    }
}

#if DASHPAY

/// The contact route's intro under its navigation bar: the design system's
/// TopIntro — a large left-aligned title, and the recipient named underneath.
///
/// `TopIntroView` draws the title. The recipient line is composed here rather
/// than passed as its `mainDescription` because the component's descriptions
/// are plain strings and this one carries an avatar; it uses the same
/// `.subhead` token, so the two read as one block. A `TopIntroView` overload
/// taking a description view would let this drop — a DashUIKit change, not one
/// to make from here.
private struct SendContactIntro: View {
    let contact: ContactItem
    /// The funding balance in duffs, shown on its own line. A contact can only
    /// be paid from Core today, so the screen states what is available rather
    /// than offering a choice. It is the fee-aware spendable figure the Send
    /// button is gated on, not the raw balance — typing the number shown here
    /// must not come back as "insufficient balance".
    let balanceDuffs: UInt64

    /// Hidden first, like the merchant pay screen: the number is here to be
    /// consulted, not broadcast to whoever is looking at the phone.
    @State private var balanceHidden = true

    private enum Layout {
        static let eyeCircleSize: CGFloat = 28
        static let eyeIconSize: CGFloat = 14
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                DashUIKit.TopIntroView(title: NSLocalizedString("Send", comment: ""))

                HStack(spacing: 6) {
                    Text(NSLocalizedString("to", comment: "Send screen: precedes the recipient"))
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                    ContactAvatarView(
                        title: contact.displayTitle,
                        avatarURL: contact.avatarURL,
                        identitySeed: contact.contactIdentityId,
                        size: 24)
                    Text(contact.displayTitle)
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                        .lineLimit(1)
                }

                // What the send has to spend, not which balance it came from:
                // a contact can only be paid from Core, so naming the source
                // says nothing the user can act on — the number does. Masked
                // until asked for, with the eye control and the hidden-first
                // default `DashSpendPayIntro` established for this same row.
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Balance:", comment: "Send screen: the funding balance"))

                    if balanceHidden {
                        Text("***********")
                    } else {
                        DashAmount(amount: Int64(balanceDuffs), font: .subheadline, showDirection: false)
                        Text("~").font(.subheadline)
                        fiatText
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { balanceHidden.toggle() }
                    }) {
                        eyeIcon
                    }
                    .buttonStyle(.plain)
                    // `eyeIcon` is two icons in a ZStack and carries no text,
                    // so VoiceOver would announce this control unnamed.
                    .accessibilityLabel(Text(balanceHidden
                        ? NSLocalizedString("Show balance", comment: "Send screen: reveal the funding balance")
                        : NSLocalizedString("Hide balance", comment: "Send screen: mask the funding balance")))
                }
                .font(.subheadline)
                .foregroundColor(Color.dash.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyeIcon: some View {
        ZStack {
            Circle()
                .fill(Color.dash.gray300Alpha10)
                .frame(width: Layout.eyeCircleSize, height: Layout.eyeCircleSize)

            Icon(name: .custom("eye_opened-icon", maxHeight: Layout.eyeIconSize))
                .foregroundColor(.dash.primaryText)
                .opacity(balanceHidden ? 1 : 0)

            Icon(name: .custom("eye_closed-icon", maxHeight: Layout.eyeIconSize))
                .foregroundColor(.dash.primaryText)
                .opacity(balanceHidden ? 0 : 1)
        }
        .compositingGroup()
    }

    @ViewBuilder
    private var fiatText: some View {
        let text = try? CurrencyExchanger.shared
            .convertDash(amount: balanceDuffs.dashAmount, to: App.fiatCurrency)
            .formattedFiatAmount

        Text(text ?? NSLocalizedString("Not available", comment: ""))
            .font(.subheadline)
            .foregroundColor(Color.dash.secondaryText)
    }
}

#endif

/// The chosen recipient, read-only — a truncated address, or a DashPay
/// contact's avatar and name when the flow was opened from the contact picker.
/// Tapping (`onEdit`) pops back to whichever step chose it. Shared by the
/// source and amount steps.
private struct SendAddressSummary: View {
    @ObservedObject var viewModel: SendViewModel
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                caption
                card
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var caption: some View {
        HStack {
            Text(isContactRecipient
                ? NSLocalizedString("To", comment: "")
                : NSLocalizedString("Address", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            // A contact has no address form to name — the row below already
            // says who is being paid.
            if !isContactRecipient, let destination = viewModel.destination {
                destinationBadge(destination)
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        #if DASHPAY
        if let contact = viewModel.contactRecipient {
            contactCard(contact)
        } else {
            addressCard
        }
        #else
        addressCard
        #endif
    }

    private var addressCard: some View {
        HStack(spacing: 8) {
            Text(truncateMiddle(viewModel.trimmedAddress, visible: 10))
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primaryText)
                .lineLimit(1)
            Spacer()
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.secondaryBackground)
        .cornerRadius(10)
    }

    #if DASHPAY
    private func contactCard(_ contact: ContactItem) -> some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: contact.displayTitle,
                avatarURL: contact.avatarURL,
                identitySeed: contact.contactIdentityId)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                // Only when it adds something: the title is already the alias
                // or profile name when one of those is known.
                if let username = contact.username?.withoutDashSuffix,
                   !username.isEmpty,
                   username != contact.displayTitle {
                    Text(username)
                        .font(.system(size: 12))
                        .foregroundColor(Color.dash.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.secondaryBackground)
        .cornerRadius(10)
    }
    #endif

    private var isContactRecipient: Bool {
        #if DASHPAY
        return viewModel.contactRecipient != nil
        #else
        return false
        #endif
    }
}

// MARK: - Shared helpers

private func sourceIconName(_ network: ChainNetwork) -> String {
    switch network {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

private func sourceTitle(_ network: ChainNetwork) -> String {
    // One source of truth: simple mode calls the Core balance "Dash Wallet".
    network.balanceName
}

private func destinationBadge(_ destination: SendViewModel.DestinationKind) -> some View {
    HStack(spacing: 4) {
        Image(systemName: destinationIconName(destination))
            .font(.system(size: 10, weight: .semibold))
        Text(destinationTitle(destination))
            .font(.caption2.weight(.semibold))
    }
    .foregroundColor(.dashBlue)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.dashBlue.opacity(0.1))
    .clipShape(Capsule())
}

private func destinationIconName(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

private func destinationTitle(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return NSLocalizedString("Transparent address", comment: "Send screen destination type")
    case .platform: return NSLocalizedString("Platform address", comment: "Send screen destination type")
    case .shielded: return NSLocalizedString("Shielded address", comment: "Send screen destination type")
    }
}

#if DASHPAY
/// Pre-send review for a DashPay contact payment. The payment is already
/// signed (`SendViewModel.prepareContactReview`), so the fee and total are
/// the exact figures of the transaction Send broadcasts.
private struct ConfirmContactSendSheet: View {
    let contact: ContactItem
    let amountDuffs: UInt64
    /// The exact fee of the signed payment.
    let feeDuffs: UInt64
    let totalDuffs: UInt64
    let fiatText: String
    var onCancel: () -> Void
    var onSend: () -> Void

    private static let dashFractionDigits = 8

    var body: some View {
        // The same parts as the L1 confirmation (`ConfirmPaymentViewController`)
        // and the internal transfer's: the design system's sheet with its title,
        // grabber and close button, the amount pair, a card of rows, and the
        // button pair. Unlike those, the To row is the design system's list-8,
        // with the contact's avatar. `selfSizing` measures the content, so nothing below may
        // grow greedily — no `Spacer`, no `maxHeight: .infinity`.
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Confirm", comment: "Payment confirmation"),
            showBackButton: .constant(false),
            onClose: onCancel
        ) {
            VStack(spacing: 0) {
                // Digits only: the component draws the Dash symbol itself, as an
                // image VoiceOver cannot name — so the pair is read as one,
                // with the unit spelled out.
                DashUIKit.SwapAmountView(
                    amount: amountDuffs.formattedDashAmountWithoutCurrencySymbol,
                    secondaryText: fiatText,
                    showDashLogo: true)
                    .padding(.top, 14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(amountDuffs.formattedDashAmount)
                    .accessibilityValue(fiatText)

                VStack(spacing: 0) {
                    DashUIKit.List8View(
                        label: NSLocalizedString("To", comment: "Payment confirmation"),
                        value: contact.displayTitle,
                        truncationMode: contact.displayTitleIsName ? .tail : .middle
                    ) {
                        ContactAvatarView(
                            title: contact.displayTitle,
                            avatarURL: contact.avatarURL,
                            identitySeed: contact.contactIdentityId,
                            size: 24)
                    }
                    // Every place a duff can occupy, as on the L1 confirmation:
                    // the component's default rounds a Core fee to "0".
                    DashUIKit.MenuItem(
                        title: NSLocalizedString("Network fee", comment: "Payment confirmation"),
                        accessory: .balance(
                            dash: Int64(clamping: feeDuffs), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits))
                    DashUIKit.MenuItem(
                        title: NSLocalizedString("Total", comment: ""),
                        accessory: .balance(
                            dash: Int64(clamping: totalDuffs), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits))
                }
                .modifier(MenuViewModifier())
                .padding(.top, 20)

                HStack(spacing: 20) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Cancel", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: onCancel)
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Send", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue,
                        action: onSend)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}
#endif

/// Middle-truncated address display shared by the screen's clipboard chip
/// and the confirm sheet's To row.
private func truncateMiddle(_ s: String, visible: Int = 8) -> String {
    guard s.count > visible * 2 + 3 else { return s }
    let head = s.prefix(visible)
    let tail = s.suffix(visible)
    return "\(head)…\(tail)"
}

// MARK: - SendConfirmSheet

/// Confirmation half-sheet for the non-core external send routes. Same
/// skeleton as `InternalTransferConfirmSheet` (summary → progress checklist →
/// success), but the To row is the recipient's address and execution runs the
/// coordinator's external-destination legs. Core → Core never reaches this
/// sheet — it rides the classic payment processor.
struct SendConfirmSheet: View {

    let route: SendViewModel.Route
    let destinationAddress: String
    /// The recipient's raw 43-byte Orchard payload — required for the
    /// shielded-destination routes (`.coreToShielded`,
    /// `.platformToShielded`, `.shieldedToShielded`), nil otherwise.
    let destinationRaw43: Data?
    let dashDuffs: Int64
    let creditsAmount: UInt64
    let fiatText: String
    /// Preflighted withdrawal fee — only meaningful for `.platformToCore`.
    var withdrawalFeeCredits: UInt64? = nil
    var isFullPlatformWithdrawal: Bool = false
    var isFullShieldedSweep: Bool = false
    var onCancel: () -> Void
    var onCompleted: () -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()

    var body: some View {
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Confirm", comment: ""),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!isInFlight),
            // Supplying `onClose` makes the close button live regardless of
            // `isDismissalEnabled`, so the protected phases have to gate it here.
            isCloseButtonEnabled: !isInFlight,
            onClose: closeAction
        ) {
            switch coordinator.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
            default:
                detailsBody
            }
        }
    }

    /// The close button has to do what the visible button of the current phase
    /// does. In the terminal phases that is `onCompleted`, which also unwinds
    /// the send flow — `onCancel` only closes the sheet, so routing every phase
    /// there would drop the user back on the amount screen with the amount
    /// still entered, one tap away from sending it twice.
    private var closeAction: () -> Void {
        switch coordinator.phase {
        case .success, .submittedUnconfirmed:
            return onCompleted
        default:
            return onCancel
        }
    }

    private var isInFlight: Bool {
        switch coordinator.phase {
        case .signing, .locking, .proving, .broadcasting:
            return true
        default:
            return false
        }
    }

    // MARK: - Idle / in-flight / failed body

    private var detailsBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: dashDuffs,
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if case let .failed(message) = coordinator.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                infoCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            switch coordinator.phase {
            case .idle:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                    positiveButtonAction: confirm,
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .failed:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Try again", comment: ""),
                    positiveButtonAction: tryAgain,
                    negativeButtonText: NSLocalizedString("Close", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .signing, .locking, .proving, .broadcasting:
                ShieldedTransferStepList(currentPhase: coordinator.phase, steps: progressSteps)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

            case .success, .submittedUnconfirmed:
                EmptyView()
            }
        }
    }

    // MARK: - Success body

    private var successBody: some View {
        VStack(spacing: 16) {
            PaymentSuccessHeader(
                title: NSLocalizedString("Sent", comment: "Send confirm sheet"),
                amountDuffs: dashDuffs,
                fiatText: fiatText)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onCompleted)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Pieces

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: fromLabel)
            divider
            HStack {
                Text(NSLocalizedString("To", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text(truncateMiddle(destinationAddress))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: networkFeeString)
            divider
            summaryRow(
                label: NSLocalizedString("Total", comment: ""),
                value: totalString)
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var fromLabel: String {
        switch route {
        case .platformToPlatform, .platformToCore, .platformToShielded:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        case .coreToCore, .coreToShielded:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dash.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dash.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Network fee estimate

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat fee estimate (credits) for the active route — same estimators as
    /// the internal transfer's confirm sheet. `nil` → the row shows "—".
    private var networkFeeCredits: UInt64? {
        switch route {
        case .coreToShielded:
            // The lock charges the fee rounded UP to a whole duff — display
            // that, so Amount + Network fee equals Total exactly.
            return CoreToShieldedAmountPolicy.currentPoolFeeDuffs.map { $0 * 1000 }
        case .platformToPlatform:
            // Credit transfer: the metered transition fee. The executor
            // states ~0.001 DASH as the conservative max.
            return 100_000_000
        case .platformToCore:
            return withdrawalFeeCredits
        case .platformToShielded:
            // The Type 15 shield is an output-only bundle padded to exactly
            // 2 actions, charged the flat base fee — same number the Rust
            // side reserves on input 0.
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .shieldedToCore:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case .shieldedToPlatform:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(kind: .unshield, numActions: 2)
        case .shieldedToShielded:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .coreToCore:
            // Never presented here — the L1 processor shows the real fee.
            return nil
        }
    }

    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    /// What actually leaves the source balance. Core→Shielded charges the
    /// pool fee on top of the amount (the executed lock value); every other
    /// route's total is the amount itself. "—" when the fee estimate is
    /// unavailable — `canContinue` fails closed before that can be confirmed,
    /// but the row must never show the un-inflated number.
    private var totalString: String {
        guard route == .coreToShielded else {
            return dashDuffs.formattedDashAmount
        }
        guard let amountDuffs = UInt64(exactly: dashDuffs),
              let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
              let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                  forAmountDuffs: amountDuffs,
                  poolFeeCredits: poolFeeCredits),
              let signedLockDuffs = Int64(exactly: lockDuffs)
        else { return "—" }
        return signedLockDuffs.formattedDashAmount
    }

    // MARK: - Info card

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: infoIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(infoTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(infoBody)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var infoIcon: String {
        switch route {
        case .platformToCore, .shieldedToCore: return "clock.fill"
        default: return "exclamationmark.shield.fill"
        }
    }

    private var infoTitle: String {
        switch route {
        case .platformToCore, .shieldedToCore:
            return NSLocalizedString("Processing time", comment: "")
        default:
            return NSLocalizedString("Double-check the address", comment: "Send confirm sheet")
        }
    }

    private var infoBody: String {
        switch route {
        case .shieldedToCore:
            return NSLocalizedString(
                "The Dash arrives at the recipient's address after the network processes the withdrawal — this can take up to 10 minutes.",
                comment: "Send confirm sheet")
        case .platformToCore:
            return isFullPlatformWithdrawal
                ? NSLocalizedString(
                    "This withdraws your entire Platform balance in one transfer. The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
                : NSLocalizedString(
                    "The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
        default:
            return NSLocalizedString(
                "Dash sent to a wrong address can't be recovered. Make sure the address is exactly the one you intend to pay.",
                comment: "Send confirm sheet")
        }
    }

    // MARK: - Progress checklist

    private var progressSteps: [ShieldedTransferStepList.Step] {
        var steps: [ShieldedTransferStepList.Step] = [
            .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing)
        ]
        // Only the asset-lock route has the on-chain locking stage.
        if route == .coreToShielded {
            steps.append(.init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking))
        }
        // Only shielded legs build an Orchard proof.
        switch route {
        case .coreToShielded, .platformToShielded, .shieldedToCore, .shieldedToPlatform,
             .shieldedToShielded:
            steps.append(.init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving))
        case .platformToPlatform, .platformToCore, .coreToCore:
            break
        }
        steps.append(.init(label: NSLocalizedString("Broadcasting", comment: ""), phase: .broadcasting))
        return steps
    }

    // MARK: - Actions

    private func confirm() {
        Task {
            switch route {
            case .coreToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performAssetLock(
                    recipientAmountDuffs: UInt64(dashDuffs),
                    recipientRaw43: destinationRaw43)
            case .platformToPlatform:
                await coordinator.performPlatformSend(
                    destination: destinationAddress,
                    amountCredits: creditsAmount)
            case .platformToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performShield(
                    amountCredits: creditsAmount,
                    recipientRaw43: destinationRaw43)
            case .platformToCore:
                await coordinator.performPlatformWithdraw(
                    amountCredits: creditsAmount,
                    fullBalance: isFullPlatformWithdrawal,
                    feeHeadroomCredits: withdrawalFeeCredits,
                    toCoreAddress: destinationAddress)
            case .shieldedToCore:
                await coordinator.performWithdraw(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep,
                    toCoreAddress: destinationAddress)
            case .shieldedToPlatform:
                await coordinator.performUnshield(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep,
                    toPlatformAddress: destinationAddress)
            case .shieldedToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performShieldedTransfer(
                    amountCredits: creditsAmount,
                    sweepAll: isFullShieldedSweep,
                    recipientRaw43: destinationRaw43)
            case .coreToCore:
                // Unreachable: the screen routes Core → Core through the L1
                // payment processor and never presents this sheet.
                break
            }
        }
    }

    private func tryAgain() {
        // If the just-failed Core → Shielded attempt already committed its
        // asset lock, RESUME that exact outpoint with the same recipient
        // instead of building a second lock (which strands the first) —
        // mirrors the internal transfer's retry.
        if route == .coreToShielded,
           let op = coordinator.lastAssetLockOutPoint,
           let destinationRaw43 {
            coordinator.reset()
            Task {
                await coordinator.resumeAssetLock(
                    outPointTxidWire: op.txidWire,
                    outPointVout: op.vout,
                    recipientRaw43: destinationRaw43)
            }
            return
        }
        coordinator.reset()
        confirm()
    }
}


/// Shared explanation for the restored-wallet initial-sync gate.
struct SyncGateNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text(NSLocalizedString(
                "Your restored wallet is completing its initial sync. Sending from your Transparent balance will be available once it finishes.",
                comment: "Core send blocked during a restored wallet's initial sync"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
}
