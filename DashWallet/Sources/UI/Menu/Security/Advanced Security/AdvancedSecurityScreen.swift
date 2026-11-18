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

struct AdvancedSecurityScreen: View {
    @ObservedObject var viewModel: AdvancedSecurityViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    DashUIKit.NavigationBarElement.back.button(action: onBack)
                },
                central: {
                    Text(NSLocalizedString("Advanced Security", comment: ""))
                        .dashFont(.subheadMedium)
                        .foregroundColor(.dash.primaryText)
                        .accessibilityAddTraits(.isHeader)
                })

            ScrollView {
                VStack(spacing: 20) {
                    SecurityLevelHeader(level: viewModel.securityLevel)
                        .padding(.top, 10)
                    autoLogoutCard
                    spendingConfirmationCard
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Reset to Default", comment: ""),
                        size: .medium,
                        style: .plainBlue,
                        action: { withAnimation { viewModel.resetToDefault() } })
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            // The onboarding preview only shows the settings.
            .allowsHitTesting(viewModel.isInteractive)
        }
        .background(Color.dash.primaryBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Auto logout

    private var autoLogoutCard: some View {
        VStack(spacing: 0) {
            DashUIKit.MenuItem(
                title: NSLocalizedString("Auto Logout", comment: ""),
                accessory: .toggle(isOn: Binding(
                    get: { viewModel.autoLogout },
                    set: { isOn in withAnimation { viewModel.setAutoLogout(isOn) } })))

            if viewModel.showsLockTimer {
                Divider()
                SliderRow(title: viewModel.lockTimerTitle) {
                    // Also a stored value that is not a slider stop.
                    Text(viewModel.lockTimerValueText)
                        .font(.system(.title2))
                        .foregroundColor(.dash.primaryText)
                } slider: {
                    SegmentSlider(
                        stopCount: AdvancedSecurityViewModel.lockTimerIntervals.count,
                        selectedIndex: viewModel.lockTimerIndex,
                        accessibilityLabel: viewModel.lockTimerTitle,
                        unselectedValueText: viewModel.lockTimerValueText,
                        valueText: { AdvancedSecurityViewModel.lockTimerText(AdvancedSecurityViewModel.lockTimerIntervals[$0]) },
                        onSelect: { viewModel.selectLockTimer(at: $0) },
                        leadingLabel: { Text(AdvancedSecurityViewModel.lockTimerText(AdvancedSecurityViewModel.lockTimerIntervals[0])) },
                        trailingLabel: { Text(AdvancedSecurityViewModel.lockTimerText(AdvancedSecurityViewModel.lockTimerIntervals.last ?? 0)) })
                }
                .transition(.opacity)
            }
        }
        .modifier(MenuViewModifier())
    }

    // MARK: - Spending confirmation

    private var spendingConfirmationCard: some View {
        VStack(spacing: 0) {
            DashUIKit.MenuItem(
                title: NSLocalizedString("Spending Confirmation", comment: ""),
                accessory: .toggle(isOn: Binding(
                    get: { viewModel.spendingConfirmationEnabled },
                    set: { isOn in withAnimation { viewModel.setSpendingConfirmation(isOn) } })))

            if viewModel.showsSpendingLimit {
                Divider()
                SliderRow(title: viewModel.spendingLimitTitle) {
                    if let amount = viewModel.spendingLimitAmount {
                        DashUIKit.DashAmount(amount: amount, fontSize: 22, weight: .regular)
                    }
                } slider: {
                    SegmentSlider(
                        stopCount: AdvancedSecurityViewModel.spendingLimits.count,
                        selectedIndex: viewModel.spendingLimitIndex,
                        accessibilityLabel: viewModel.spendingLimitTitle,
                        unselectedValueText: viewModel.spendingLimitValueText,
                        valueText: { Int64(clamping: AdvancedSecurityViewModel.spendingLimits[$0]).formattedDashAmount },
                        onSelect: { viewModel.selectSpendingLimit(at: $0) },
                        leadingLabel: {
                            DashUIKit.DashAmount(amount: Int64(clamping: AdvancedSecurityViewModel.spendingLimits[0]))
                        },
                        trailingLabel: {
                            DashUIKit.DashAmount(amount: Int64(clamping: AdvancedSecurityViewModel.spendingLimits.last ?? 0))
                        })
                } footer: {
                    spendingLimitDescription
                }
                .transition(.opacity)
            }
        }
        .modifier(MenuViewModifier())
    }

    private var spendingLimitDescription: Text {
        let sentence = Text(viewModel.spendingLimitDescription)
            .foregroundColor(.dash.secondaryText)
        guard viewModel.descriptionShowsAmount, let amount = viewModel.spendingLimitAmount else {
            return sentence
        }
        return sentence + Text(" ") + Text(amount.formattedDashAmount).foregroundColor(.dash.primaryText)
    }
}

// MARK: - Security level header

private struct SecurityLevelHeader: View {
    let level: WalletSecurityLevel

    var body: some View {
        VStack(spacing: 6) {
            Image(level == .none ? "icon_security_excl" : "icon_security_ok")
                .renderingMode(.template)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(NSLocalizedString("Security Level", comment: ""))
                .font(.system(.footnote))
                .foregroundColor(.dash.secondaryText)
            Text(title)
                .font(.system(.title3))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch level {
        case .none: return NSLocalizedString("None", comment: "adjective, security level")
        case .low: return NSLocalizedString("Low", comment: "adjective, security level")
        case .medium: return NSLocalizedString("Medium", comment: "adjective, security level")
        case .high: return NSLocalizedString("High", comment: "adjective, security level")
        case .veryHigh: return NSLocalizedString("Very High", comment: "adjective, security level")
        }
    }

    private var color: Color {
        switch level {
        case .none: return .dash.red
        case .low, .medium: return .dash.orange
        case .high: return .dash.blue
        case .veryHigh: return .dash.green
        }
    }
}

// MARK: - Slider row

/// A card row: title and current value, the slider, and an optional note.
private struct SliderRow<Detail: View, Slider: View, Footer: View>: View {
    let title: String
    @ViewBuilder let detail: Detail
    @ViewBuilder let slider: Slider
    @ViewBuilder let footer: Footer

    init(
        title: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder slider: () -> Slider,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail()
        self.slider = slider()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.callout))
                    .foregroundColor(.dash.primaryText)
                Spacer(minLength: 8)
                detail
            }
            slider
            footer
                .font(.system(.footnote))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Hosting

/// Hosts `AdvancedSecurityScreen` in a UIKit navigation stack. Like the
/// Objective-C screen it replaces, it pops itself when the app resigns active,
/// so the settings are never left open behind the lock screen.
final class AdvancedSecurityHostingController: UIHostingController<AdvancedSecurityScreen> {
    /// Lets the screen's back button, built before `super.init`, reach the
    /// controller without a strong reference back to it.
    private final class ActionTarget {
        weak var controller: AdvancedSecurityHostingController?
    }

    private var resignActiveObserver: NSObjectProtocol?

    init(viewModel: AdvancedSecurityViewModel) {
        let target = ActionTarget()
        super.init(rootView: AdvancedSecurityScreen(
            viewModel: viewModel,
            onBack: { target.controller?.navigationController?.popViewController(animated: true) }))
        target.controller = self
        hidesBottomBarWhenPushed = true
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.navigationController?.popViewController(animated: true)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    /// The wallet's own settings.
    static func live() -> AdvancedSecurityHostingController {
        AdvancedSecurityHostingController(viewModel: AdvancedSecurityViewModel(
            store: LiveAdvancedSecuritySettingsStore()))
    }

    /// The onboarding preview: recommended settings, not interactive.
    static func demo() -> AdvancedSecurityHostingController {
        AdvancedSecurityHostingController(viewModel: AdvancedSecurityViewModel(
            store: DemoAdvancedSecuritySettingsStore(),
            isInteractive: false))
    }
}

/// Builds the Advanced Security screen for Objective-C callers (onboarding),
/// which can't see the generic hosting controller.
@objc(DWAdvancedSecurityScreenFactory)
final class AdvancedSecurityScreenFactory: NSObject {
    @objc static func demoController() -> UIViewController {
        AdvancedSecurityHostingController.demo()
    }
}
