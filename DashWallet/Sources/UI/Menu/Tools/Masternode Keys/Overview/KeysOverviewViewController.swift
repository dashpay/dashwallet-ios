//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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
import UIKit

// MARK: - KeysOverviewViewController

/// Hosts `KeysOverviewContentView`, which draws its own DashUIKit bar: the
/// system bar is hidden for every `UIHostingController`.
@objc(DWKeysOverviewViewController)
final class KeysOverviewViewController: UIHostingController<KeysOverviewContentView> {
    init() {
        // The closures need `self`, which exists only after `super.init`.
        super.init(rootView: KeysOverviewContentView(onBack: {}, onOpenKey: { _ in }))
        rootView = KeysOverviewContentView(
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onOpenKey: { [weak self] key in self?.openKey(key) })
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_secondaryBackground()
    }

    /// The keys are private material, so the list opens only after the PIN.
    private func openKey(_ key: MNKey) {
        AuthenticationService.shared.authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: false,
            alertIfLockout: true
        ) { [weak self] authenticated, _, _ in
            guard authenticated else { return }

            DispatchQueue.main.async {
                let vc = DerivationPathKeysViewController(with: key)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}
