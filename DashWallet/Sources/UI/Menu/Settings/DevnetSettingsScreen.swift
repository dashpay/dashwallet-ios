//
//  DevnetSettingsScreen.swift
//  DashWallet
//
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
import UIKit

// MARK: - DevnetSettingsViewModel

/// Settings → Devnet Settings. Edits the three user-editable devnet values
/// (`DevnetConfiguration`) and, when the wallet is already running on
/// devnet, restarts the runtime so a changed quorum URL / devnet name takes
/// effect immediately (the SDK reads them only at build/SPV-start time).
@MainActor
final class DevnetSettingsViewModel: ObservableObject {
    @Published var quorumURL: String
    @Published var devnetName: String
    @Published var dashConnectContractId: String
    @Published var statusMessage: String?

    /// The last-applied values, to detect whether a save changed anything
    /// the running devnet SDK/SPV depends on. Refreshed after each save so a
    /// second, identical save doesn't restart the runtime again.
    private var initialQuorumURL: String
    private var initialDevnetName: String

    init() {
        let quorum = DevnetConfiguration.quorumURL ?? ""
        let name = DevnetConfiguration.devnetName ?? ""
        quorumURL = quorum
        devnetName = name
        dashConnectContractId = DevnetConfiguration.dashConnectContractId ?? ""
        initialQuorumURL = quorum
        initialDevnetName = name
    }

    func save() {
        DevnetConfiguration.setQuorumURL(quorumURL)
        DevnetConfiguration.setDevnetName(devnetName)
        DevnetConfiguration.setDashConnectContractId(dashConnectContractId)

        let savedQuorumURL = DevnetConfiguration.quorumURL ?? ""
        let savedDevnetName = DevnetConfiguration.devnetName ?? ""
        let networkValuesChanged =
            savedQuorumURL != initialQuorumURL || savedDevnetName != initialDevnetName
        initialQuorumURL = savedQuorumURL
        initialDevnetName = savedDevnetName

        guard WalletEnvironment.isDevnet else {
            statusMessage = NSLocalizedString(
                "Saved. The values apply when you switch to Devnet.",
                comment: "Devnet")
            return
        }

        guard DevnetConfiguration.isConfigured else {
            statusMessage = NSLocalizedString(
                "Saved, but Devnet needs both a Quorum URL and a Devnet Name — syncing will fail until both are set.",
                comment: "Devnet")
            return
        }

        guard networkValuesChanged else {
            // The contract id is read per DashConnect approval; no runtime
            // restart is needed for it.
            statusMessage = NSLocalizedString("Saved.", comment: "Devnet")
            return
        }

        // Full stop → start pair on the runtime's serial lifecycle queue:
        // the SDK re-init re-reads `platformQuorumURL` (re-discovering DAPI
        // nodes) and the SPV restart re-reads the peers + devnet name — the
        // same effect a network switch has, without changing the selection.
        // (`startIfReady` alone would elide the refresh while the runtime is
        // ready, so the explicit stop comes first.)
        SwiftDashSDKWalletRuntime.stop()
        SwiftDashSDKWalletRuntime.startIfReady()
        statusMessage = NSLocalizedString(
            "Saved. Devnet is reconnecting with the new settings.",
            comment: "Devnet")
    }
}

// MARK: - DevnetSettingsScreen

struct DevnetSettingsScreen: View {
    private let onBack: () -> Void
    @StateObject private var viewModel = DevnetSettingsViewModel()

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                onBack()
            }

            TopIntro(title: NSLocalizedString("Devnet Settings", comment: "Devnet"))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(
                        title: NSLocalizedString("Quorum URL", comment: "Devnet"),
                        placeholder: "https://quorums.<devnet>.networks.dash.org",
                        text: $viewModel.quorumURL,
                        keyboard: .URL,
                        helper: NSLocalizedString(
                            "Base URL of the devnet's quorum-list server. SPV peers and Platform (DAPI) nodes are both auto-discovered from {Quorum URL}/masternodes — no manual peer entry.",
                            comment: "Devnet"))

                    field(
                        title: NSLocalizedString("Devnet Name", comment: "Devnet"),
                        placeholder: NSLocalizedString("e.g. moutai (matches dashd -devnet=<name>)", comment: "Devnet"),
                        text: $viewModel.devnetName,
                        keyboard: .default,
                        helper: NSLocalizedString(
                            "The devnet chain name. It is embedded in the sync user agent (devnet.devnet-<name>) — devnet nodes reject connections without it.",
                            comment: "Devnet"))

                    field(
                        title: NSLocalizedString("DashConnect Contract ID", comment: "Devnet"),
                        placeholder: NSLocalizedString("Base58 identifier (optional)", comment: "Devnet"),
                        text: $viewModel.dashConnectContractId,
                        keyboard: .default,
                        helper: NSLocalizedString(
                            "The loginKeyResponse data contract id registered on this devnet. Only needed for DashConnect logins; leave empty otherwise.",
                            comment: "Devnet"))

                    DashButton(
                        text: NSLocalizedString("Save", comment: ""),
                        style: .filled,
                        size: .large
                    ) {
                        viewModel.save()
                    }
                    .padding(.top, 4)

                    if let status = viewModel.statusMessage {
                        Text(status)
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(Color.dash.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        helper: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .dashFont(.subheadMedium)
                .foregroundColor(Color.dash.primaryText)

            TextField(placeholder, text: text)
                .font(.system(.footnote, design: .monospaced))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.dash.primaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(helper)
                .dashFont(.caption1)
                .foregroundColor(Color.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hosting controller

/// UIKit bridge for the Settings navigation stack, mirroring the sibling
/// hosting controllers in `SettingsScreen.swift`.
final class DevnetSettingsHostingViewController: BaseViewController {
    private weak var navController: UINavigationController?

    init(vc: UINavigationController) {
        navController = vc
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let rootView = DevnetSettingsScreen(onBack: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension DevnetSettingsHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}
