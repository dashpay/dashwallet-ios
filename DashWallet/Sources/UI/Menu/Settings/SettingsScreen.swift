//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import UIKit
import SwiftUI
import DashUIKit
import Combine
import MessageUI

struct SettingsScreen: View {
    private let vc: UINavigationController
    // Retained solely for the frozen MainMenuViewController call site; the
    // rescan controls were removed with the dead DashSync rescan actions
    // (post-M6 there is no SDK rescan API), so this closure is never invoked.
    private let onDidRescan: () -> ()

    @StateObject private var viewModel = SettingsMenuViewModel()
    @State private var showNetworkAlert = false
    @State private var showCSVExportActivity = false

    init(vc: UINavigationController, onDidRescan: @escaping () -> ()) {
        self.vc = vc
        self.onDidRescan = onDidRescan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Settings", comment: ""))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Menu list
            VStack(spacing: 2) {
                ForEach(viewModel.items) { item in
                    row(for: item)
                        .frame(minHeight: 60)
                }
            }
            .padding(6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showCSVExportActivity) { show in
            showCSVExportActivity = show
        }
        .alert(NSLocalizedString("Network", comment: ""), isPresented: $showNetworkAlert) {
            Button(NSLocalizedString("Mainnet", comment: "")) {
                Task {
                    let success = await viewModel.switchToMainnet()
                    if success {
                        updateView()
                    }
                }
            }
            Button(NSLocalizedString("Testnet", comment: "")) {
                Task {
                    let success = await viewModel.switchToTestnet()
                    if success {
                        updateView()
                    }
                }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
        .sheet(isPresented: $viewModel.showAdvancedModeInfo) {
            DashUIKit.BottomSheet.selfSizing(
                title: NSLocalizedString("Advanced mode", comment: "Settings"),
                showBackButton: .constant(false)
            ) {
                // TODO(advanced-mode): the copy lands here once the surfaces
                // the flag gates are decided. Until then this says only what is
                // true of the build it ships in.
                Text(NSLocalizedString(
                    "Reveals extra wallet details and actions intended for experienced users. Turning it off hides them again; nothing about your funds changes either way.",
                    comment: "Settings"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .alert(NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"), isPresented: $viewModel.showCoinJoinSweepConfirmation) {
            Button(NSLocalizedString("Move funds", comment: "CoinJoin")) {
                Task { await viewModel.performCoinJoinSweep() }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("Move your %@ in mixed coins to your spendable balance? CoinJoin is no longer supported.", comment: "CoinJoin"), viewModel.coinJoinLeftoverFormatted))
        }
        .alert(
            NSLocalizedString("Move CoinJoin Funds", comment: "CoinJoin"),
            isPresented: Binding(
                get: { viewModel.coinJoinSweepErrorMessage != nil },
                set: { if !$0 { viewModel.coinJoinSweepErrorMessage = nil } }
            ),
            presenting: viewModel.coinJoinSweepErrorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "")) { viewModel.coinJoinSweepErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showCSVExportActivity) {
            if let csvData = viewModel.csvExportData {
                ActivityView(activityItems: [csvData.file])
            }
        }
    }
    
    // MARK: - Rows

    /// One settings row, rendered by the design system's `MenuItem`.
    ///
    /// `DashUIKit.MenuItem` draws the row and nothing else — it carries no tap
    /// handler of its own — so what a tap means is decided here, per row:
    ///
    /// - a switch owns its own gesture, so a plain toggle row is not wrapped;
    /// - a row that also has something to explain puts the explanation on the
    ///   row body, leaving the switch to toggle and the rest to inform (the
    ///   info glyph is drawn by `MenuItem` but is not itself a button);
    /// - everything else is a button that runs the row's action.
    @ViewBuilder
    private func row(for item: MenuItemModel) -> some View {
        let content = DashUIKit.MenuItem(
            leadingIcon: item.icon.map(Self.iconSource),
            title: item.title,
            helpText: item.subtitle,
            infoIcon: item.showInfo ? .system("info.circle.fill") : nil,
            accessory: item.showToggle
                ? .toggle(isOn: Self.toggleBinding(item))
                : (item.details.map { .text($0) } ?? .none)
        )

        if item.showToggle {
            if let infoAction = item.infoAction {
                // The switch owns its own tap, so the rest of the row is free
                // to answer the question the info glyph poses.
                Button(action: infoAction) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        } else if let action = item.action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Writing through the switch runs the row's action, which is what the
    /// view model already uses to flip the underlying setting; the getter stays
    /// the model's value so a refresh is what moves the switch.
    private static func toggleBinding(_ item: MenuItemModel) -> Binding<Bool> {
        Binding(
            get: { item.isToggled },
            set: { _ in item.action?() }
        )
    }

    /// `IconName` predates `DashIconSource` and says the same things. The one
    /// field with no counterpart is `maxHeight`: `MenuItem` sizes its own icon.
    private static func iconSource(_ icon: IconName) -> DashIconSource {
        switch icon {
        case .system(let name):
            .system(name)
        case .custom(let name, let bundle, _):
            .custom(name, bundle: bundle)
        case .image(let uiImage, _):
            .uiImage(uiImage)
        }
    }

    private func handleNavigation(_ destination: SettingsMenuNavigationDestination?) {
        switch destination {
        case .currencySelector:
            showCurrencySelector()
        case .network:
            showNetworkAlert = true
        case .about:
            showAboutController()
        case .exportCSV:
            handleCSVExport()
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    private func showCurrencySelector() {
        let view = LocalCurrencyView(
            currencyCode: nil,
            onSelect: { [weak vc] _ in
                vc?.popViewController(animated: true)
            },
            onBack: { [weak vc] in
                vc?.popViewController(animated: true)
            }
        )
        let controller = LocalCurrencyHostingViewController(rootView: view)
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func showAboutController() {
        let controller = AboutDashHostingViewController()
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    
    private func handleCSVExport() {
        Task {
            do {
                try await viewModel.exportCSV()
            } catch {
                // Handle error display if needed
            }
        }
    }
    
    private func updateView() {
        // Trigger view refresh after network change
        viewModel.resetNavigation()
    }
}



private final class LocalCurrencyHostingViewController: BaseViewController {
    private let rootView: LocalCurrencyView

    init(rootView: LocalCurrencyView) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension LocalCurrencyHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

private final class AboutDashHostingViewController: BaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()

        let rootView = AboutDashView(
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onContactSupport: { [weak self] in
                self?.presentSupportEmailController()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        dw_embedChild(hostingController)
    }
}

extension AboutDashHostingViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

extension AboutDashHostingViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}
