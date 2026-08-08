//
//  ContactProfileSheet.swift
//  DashWallet
//
//  Contact profile: header, actions, settings and payment history.
//

import SwiftUI
import DashUIKit

struct ContactProfileSheet: View {
    @StateObject private var viewModel: ContactProfileViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaySheet = false
    @State private var selectedPaymentId: String? = nil
    @State private var showContactSettings = false

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor and `ContactProfileViewModel` is
    /// `@MainActor`. `StateObject`'s autoclosure defers construction to view
    /// installation. Previews pass one in.
    init(contact: ContactItem, viewModel: ContactProfileViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? ContactProfileViewModel(contact: contact))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        if let message = viewModel.contact.publicMessage, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 14))
                                .foregroundColor(.dash.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        actions
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedPaymentId) { paymentId in
                // Reuse the standard tx-detail screen. The SwiftUI
                // NavigationStack supplies the back button (nav bar left
                // visible), so we don't drive TXDetailVCWrapper's own
                // programmatic pop.
                if let tx = viewModel.resolvedByTxid[paymentId] {
                    TXDetailVCWrapper(tx: tx, navigateBack: .constant(false))
                        .navigationTitle(NSLocalizedString("Transaction", comment: "DashPay Contacts"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showingPaySheet) {
                PayContactSheet(contact: viewModel.contact)
            }
            .onAppear { viewModel.onAppear() }
            .onChange(of: viewModel.shouldDismiss) { _, close in
                if close { dismiss() }
            }
            .overlay(alignment: .bottom) {
                if viewModel.metaSavedToast {
                    Text(NSLocalizedString("Saved", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ContactAvatarView(
                title: viewModel.contact.displayTitle,
                avatarURL: viewModel.contact.avatarURL,
                identitySeed: viewModel.contact.contactIdentityId,
                size: 88)
            Text(viewModel.contact.displayTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            if let username = viewModel.contact.username?.withoutDashSuffix,
               !username.isEmpty,
               username != viewModel.contact.displayTitle {
                Text(username)
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
            }
            if viewModel.contact.relationship == .established {
                // Disclosure hint: tapping the header toggles the
                // Contact settings card below.
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.tertiaryText)
                    .rotationEffect(.degrees(showContactSettings ? 180 : 0))
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.contact.relationship == .established else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showContactSettings.toggle()
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch viewModel.contact.relationship {
        case .incoming:
            // Android "contact request received" pane: caption title +
            // green Accept / tertiary Ignore pair (120×39, radius 8).
            VStack(spacing: 14) {
                Text(String(
                    format: NSLocalizedString("%@ has requested to be your contact", comment: "DashPay Contacts"),
                    viewModel.contact.displayTitle))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                if viewModel.isProcessing {
                    SwiftUI.ProgressView()
                } else {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.accept()
                        } label: {
                            Text(NSLocalizedString("Accept", comment: "DashPay Contacts"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.dash.whiteText)
                                .frame(width: 120, height: 39)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.dashGreen))
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.ignore()
                        } label: {
                            Text(NSLocalizedString("Ignore", comment: "DashPay Contacts"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.dash.primaryText)
                                .frame(width: 120, height: 39)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.dash.gray300Alpha10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 32)
        case .outgoing:
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12))
                Text(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.dashGolden)
        case .established:
            VStack(spacing: 20) {
                // Contact settings unfold from under the header when
                // the user taps the contact's name/avatar. zIndex(-1)
                // keeps the card BEHIND its siblings while the move
                // transition runs — without it the inserted view is
                // rendered on top and slides over the Pay button.
                if showContactSettings {
                    metaSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(-1)
                }

                // Android Button.Primary.Blue: full-width filled pay CTA.
                Button {
                    showingPaySheet = true
                } label: {
                    Label(
                        NSLocalizedString("Pay", comment: "DashPay Contacts"),
                        systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.dash.whiteText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.blue))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                paymentsSection

                Button {
                    viewModel.toggleHidden()
                } label: {
                    Label(
                        viewModel.isHidden
                            ? NSLocalizedString("Unhide Contact", comment: "DashPay Contacts")
                            : NSLocalizedString("Hide Contact", comment: "DashPay Contacts"),
                        systemImage: viewModel.isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.gray300Alpha10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 15)
            }
        }
    }

    // MARK: Owner-private meta (alias / note) — "Contact settings" card

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Contact settings", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString("Only visible to you", comment: "DashPay Contacts"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            TextField(
                NSLocalizedString("Alias", comment: "DashPay Contacts"),
                text: $viewModel.aliasText)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dash.primaryBackground))
                .onSubmit { viewModel.saveMeta() }
            TextField(
                NSLocalizedString("Note", comment: "DashPay Contacts"),
                text: $viewModel.noteText,
                axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dash.primaryBackground))
                .onSubmit { viewModel.saveMeta() }
            if viewModel.metaChanged {
                Button {
                    viewModel.saveMeta()
                } label: {
                    Text(NSLocalizedString("Save", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dash.blue)
                        .frame(height: 30)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 15)
    }

    // MARK: Payments between us — history card

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Payments", comment: "DashPay Contacts"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            // Legacy profile's info tooltip, inlined: only payments
            // that flowed through the DashPay contact channel appear
            // here — direct-to-address sends are not retained.
            Text(NSLocalizedString("Payments made directly to an address aren't retained here.", comment: "DashPay Contacts"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            if viewModel.payments.isEmpty {
                Text(NSLocalizedString("No viewModel.payments with this contact yet", comment: "DashPay Contacts"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .padding(.top, 2)
            } else {
                ForEach(viewModel.payments) { payment in
                    paymentRow(payment)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 15)
    }

    /// One payment row. Tappable → the standard tx-detail screen when
    /// the on-chain transaction resolves in this wallet's store; a plain
    /// row otherwise (H1-lost sends, or a received tx not yet synced).
    @ViewBuilder
    private func paymentRow(_ payment: SwiftDashSDKContactsService.ContactPayment) -> some View {
        let resolvedTx = viewModel.resolvedByTxid[payment.id]
        HStack(spacing: 10) {
            Image(systemName: payment.direction == .sent
                ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(payment.direction == .sent ? .dash.blue : .dashGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(payment.direction == .sent ? "-" : "+")\(ContactProfileViewModel.dashString(duffs: payment.amountDuffs)) DASH")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                if let fiat = payment.fiatString {
                    Text(fiat)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.secondaryText)
                }
                if let memo = payment.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
            if resolvedTx != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if resolvedTx != nil { selectedPaymentId = payment.id }
        }
    }

    /// Fetch the payment history and resolve each row's on-chain tx
    /// (main-thread SwiftData reads; a handful of rows, <10ms each).
}

// MARK: - PayContactSheet

/// Minimal pay-to-contact amount sheet (Row #18 phase 6). The Pay
/// button is the explicit user confirmation; tapping it runs the
/// spend-auth gate and then the single-shot SDK payment (which
/// derives the contact's DIP-15 receive address Rust-side, then
/// builds + signs + broadcasts). The network fee is charged by the
/// SDK on top of the entered amount — the cap below uses
/// `maxSendable` (spendable minus a conservative fee reserve) so the
/// fee can't push the send over the balance.

#if DEBUG

/// No contacts service behind these, so nothing syncs and the actions are
/// no-ops. Payment rows are left empty on purpose: a row needs a wallet
/// `Transaction` to resolve against, which cannot be fabricated app-side.
#Preview("Established") {
    ContactProfileSheet(
        contact: .preview(title: "briantest63a"),
        viewModel: .preview(contact: .preview(title: "briantest63a")))
}

#Preview("Incoming request") {
    ContactProfileSheet(
        contact: .preview(title: "s22test63b", relationship: .incoming),
        viewModel: .preview(
            contact: .preview(title: "s22test63b", relationship: .incoming)))
}

#endif
