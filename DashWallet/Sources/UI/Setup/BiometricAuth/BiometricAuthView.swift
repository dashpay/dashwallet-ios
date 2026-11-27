//
//  Created by Dash Core Group
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

import LocalAuthentication
import SwiftUI

// MARK: - BiometricAuthViewModel

/// Offers Face ID or Touch ID during wallet setup. Either answer is final:
/// the question is not asked again.
@MainActor
final class BiometricAuthViewModel: ObservableObject {
    /// Off while the system biometrics prompt is up.
    @Published private(set) var isEnabled = true

    /// Called once the user has enabled or skipped biometrics.
    var onFinish: (() -> Void)?

    private let model = DWBiometricAuthModel()

    /// Whether setup should offer biometrics: not answered yet, and there is
    /// Face ID or Touch ID to use.
    static var shouldOffer: Bool {
        DWBiometricAuthModel.shouldEnableBiometricAuthentication
            && DWBiometricAuthModel.biometricAuthenticationAvailable
    }

    var icon: String {
        model.biometryType == .faceID ? "icon_faceid" : "icon_touchid"
    }

    var title: String {
        model.biometryType == .faceID
            ? String(localized: "Login with Face ID", comment: "")
            : String(localized: "Login with Touch ID", comment: "")
    }

    var enableTitle: String {
        model.biometryType == .faceID
            ? String(localized: "Enable Face ID", comment: "")
            : String(localized: "Enable Touch ID", comment: "")
    }

    func enable() {
        isEnabled = false
        model.enableBiometricAuth { [weak self] _ in
            // A failure does not send the user to Settings: iOS would end the
            // app when the setting changed, and with it the wallet setup.
            DispatchQueue.main.async { self?.onFinish?() }
        }
    }

    func skip() {
        model.disableBiometricAuth()
        onFinish?()
    }
}

// MARK: - BiometricAuthView

struct BiometricAuthView: View {
    @ObservedObject var viewModel: BiometricAuthViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(viewModel.icon)
                    .accessibilityHidden(true)
                Text(viewModel.title)
                    .font(.system(.title3))
                    .foregroundColor(Color("DarkTitleColor"))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
            // Centred from the top of the screen, not from under the status
            // bar, as before.
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                Button(viewModel.enableTitle, action: viewModel.enable)
                    .buttonStyle(SetupActionButtonStyle())
                Button(String(localized: "Skip", comment: ""), action: viewModel.skip)
                    .buttonStyle(SetupTextButtonStyle())
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .disabled(!viewModel.isEnabled)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
    }
}

// MARK: - BiometricAuthViewController

/// Hosts `BiometricAuthView` in wallet setup.
final class BiometricAuthViewController: UIViewController, NavigationFullscreenable {
    var onFinish: (() -> Void)? {
        get { viewModel.onFinish }
        set { viewModel.onFinish = newValue }
    }

    private let viewModel = BiometricAuthViewModel()

    var requiresNoNavigationBar: Bool { true }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        embedSwiftUI(BiometricAuthView(viewModel: viewModel))
    }
}
