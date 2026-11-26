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

import SwiftUI

// MARK: - VerifiedSuccessfullyView

/// The end of the backup: the recovery phrase has been verified.
struct VerifiedSuccessfullyView: View {
    var onContinue: () -> Void = { }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Image("icon_security")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color.dash.blue)
                        .frame(width: 75, height: 96)
                        .accessibilityHidden(true)

                    Text(String(localized: "Verified Successfully", comment: ""))
                        .font(.system(.title3))
                        .foregroundColor(Color("DarkTitleColor"))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 28)

                    Text(String(localized: "Your wallet is secured now. You can use your recovery phrase anytime to recover your account on another device.",
                                comment: ""))
                        .font(.system(.callout))
                        .foregroundColor(Color("SecondaryTextColor"))
                        .padding(.top, 14)

                    Button(String(localized: "Continue", comment: ""), action: onContinue)
                        .buttonStyle(VerifiedContinueButtonStyle())
                        .padding(.top, 24)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Centred on the screen, scrolling when it does not fit.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
    }
}

/// The compact Dash blue button the screen had: as wide as its title.
private struct VerifiedContinueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledSystemFont(size: 15, weight: .medium, relativeTo: .subheadline)
            .foregroundColor(configuration.isPressed ? Color.dash.blue : .white)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 39)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.clear : Color.dash.blue)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.dash.blue, lineWidth: configuration.isPressed ? 2 : 0)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - VerifiedSuccessfullyViewController

/// Hosts `VerifiedSuccessfullyView`; Continue hands back to the delegate.
@objc(DWVerifiedSuccessfullyViewController)
final class VerifiedSuccessfullyViewController: UIViewController, NavigationFullscreenable {
    @objc weak var delegate: DWSecureWalletDelegate?

    var requiresNoNavigationBar: Bool { true }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        embedSwiftUI(VerifiedSuccessfullyView(onContinue: { [weak self] in
            guard let self else { return }
            self.delegate?.secureWalletRoutineDidFinish(self)
        }))
    }
}
