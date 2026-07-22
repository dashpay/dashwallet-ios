//
//  ClaimInvitationScreen.swift
//  DashWallet
//
//  Redeem a DashPay invitation (DIP-13): paste or scan the invitation
//  link, preview the inviter, and hand the normalized URI to the
//  create-username flow, which claims the voucher through
//  `DWIdentityRegistrationCoordinator.startClaimInvitation`.
//
//  Reached two ways:
//    - a `dashpay://invite` / applink deep link (prefilled, field
//      already populated);
//    - manually from the Join DashPay dialog ("Have an invitation?")
//      for the install-then-paste flow — the invitee installed the app
//      first and brings the link over by paste or QR scan.
//

import SwiftUI
import DashUIKit
import UIKit

/// Push-based navigation glue shared by every redeem entry (deep link,
/// Home join dialog, menu join dialog): redeem screen → username form
/// in invitation mode. Kept here so the entries can't drift apart.
@MainActor
enum ClaimInvitationFlow {

    /// Push the redeem screen; its Continue pushes the create-username
    /// form claiming the normalized URI. `initialLink` prefills the
    /// field (deep link); nil is the manual paste/scan entry.
    static func pushRedeemScreen(
        on navigation: UINavigationController?,
        dashPayModel: DWDashPayProtocol,
        initialLink: String? = nil,
        definedUsername: String? = nil,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        guard let navigation else { return }
        let screen = ClaimInvitationScreen(initialLink: initialLink) { [weak navigation] uri in
            guard let navigation else { return }
            let controller = CreateUsernameViewController(
                dashPayModel: dashPayModel,
                invitationURL: URL(string: uri),
                definedUsername: definedUsername)
            controller.hidesBottomBarWhenPushed = true
            controller.completionHandler = completionHandler
            navigation.pushViewController(controller, animated: true)
        }
        let hosting = UIHostingController(rootView: screen)
        hosting.view.backgroundColor = UIColor.dw_secondaryBackground()
        hosting.hidesBottomBarWhenPushed = true
        navigation.pushViewController(hosting, animated: true)
    }
}

@MainActor
final class ClaimInvitationViewModel: ObservableObject {

    enum LinkState: Equatable {
        /// Nothing entered yet.
        case empty
        /// Entered text is not a structurally valid invitation link.
        case invalid
        /// Recognized + structurally valid; `normalizedURI` is set.
        case valid
        /// This wallet already has a DashPay identity — claiming would
        /// register a second one, which dashwallet doesn't support.
        case alreadyRegistered
    }

    @Published var input: String = ""
    @Published private(set) var state: LinkState = .empty
    @Published private(set) var normalizedURI: String? = nil
    /// The inviter's DPNS username (`du`) when the link carries one.
    @Published private(set) var inviterUsername: String? = nil

    private let service: DWInvitationServicing

    init(service: DWInvitationServicing = DWInvitationService.shared) {
        self.service = service
    }

    func evaluate() {
        guard !service.hasLocalIdentity else {
            state = .alreadyRegistered
            normalizedURI = nil
            inviterUsername = nil
            return
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .empty
            normalizedURI = nil
            inviterUsername = nil
            return
        }
        guard let uri = service.normalize(trimmed),
              let preview = service.preview(for: uri),
              preview.structurallyValid else {
            state = .invalid
            normalizedURI = nil
            inviterUsername = nil
            return
        }
        normalizedURI = uri
        inviterUsername = preview.hasInviter ? preview.inviterUsername : nil
        state = .valid
    }
}

struct ClaimInvitationScreen: View {
    @StateObject private var viewModel = ClaimInvitationViewModel()
    @State private var showScanner = false
    @FocusState private var isInputFocused: Bool

    /// Prefill from a deep link; nil for the manual paste/scan entry.
    let initialLink: String?
    /// Called with the normalized invitation URI when the user
    /// continues to the username form.
    var onContinue: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Claim your invitation", comment: "DashPay Invitations"))
                .foregroundColor(.dash.primaryText)
                .font(.title1)
                .padding(.top, 12)
            Text(NSLocalizedString("Paste the invitation link you received, or scan its QR code. It funds your username registration.", comment: "DashPay Invitations"))
                .foregroundColor(.dash.secondaryText)
                .font(.system(size: 14))
                .padding(.top, 4)

            TextField(
                "dashpay://invite?…",
                text: $viewModel.input,
                axis: .vertical
            )
            .font(.system(size: 14, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .lineLimit(2...5)
            .focused($isInputFocused)
            .padding(12)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 20)

            Button {
                showScanner = true
            } label: {
                Label(
                    NSLocalizedString("Scan QR code", comment: "DashPay Invitations"),
                    systemImage: "qrcode.viewfinder")
                    .font(.subheadline)
            }
            .padding(.top, 12)

            feedback
                .padding(.top, 20)

            Spacer()

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                isEnabled: viewModel.state == .valid
            ) {
                guard let uri = viewModel.normalizedURI else { return }
                onContinue(uri)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showScanner) {
            GenericQRScannerView(
                onQRCodeScanned: { value in
                    viewModel.input = value
                    showScanner = false
                },
                onCancel: { showScanner = false })
        }
        .onAppear {
            if let initialLink, viewModel.input.isEmpty {
                viewModel.input = initialLink
            } else {
                isInputFocused = true
            }
            viewModel.evaluate()
        }
        .onChange(of: viewModel.input) { _ in
            viewModel.evaluate()
        }
    }

    @ViewBuilder
    private var feedback: some View {
        switch viewModel.state {
        case .empty:
            EmptyView()

        case .invalid:
            Label(
                NSLocalizedString("This is not a valid invitation link", comment: "DashPay Invitations"),
                systemImage: "xmark.octagon")
                .font(.subheadline)
                .foregroundColor(.red)

        case .alreadyRegistered:
            Label(
                NSLocalizedString("You cannot claim this invite since you already have a Dash username", comment: ""),
                systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline)
                .foregroundColor(.orange)

        case .valid:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope.open")
                    .foregroundColor(.dash.blue)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 4) {
                    if let inviter = viewModel.inviterUsername {
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("Invitation from %@", comment: "DashPay Invitations"),
                            inviter))
                            .font(.subheadline.bold())
                            .foregroundColor(.dash.primaryText)
                    } else {
                        Text(NSLocalizedString("Valid invitation", comment: "DashPay Invitations"))
                            .font(.subheadline.bold())
                            .foregroundColor(.dash.primaryText)
                    }
                    // The voucher amount is not in the link — it is read
                    // from the funding transaction during the claim — so
                    // no amount is shown here.
                    Text(NSLocalizedString("Continue to pick your username. The invitation pays the registration fee.", comment: "DashPay Invitations"))
                        .font(.caption)
                        .foregroundColor(.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dash.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
