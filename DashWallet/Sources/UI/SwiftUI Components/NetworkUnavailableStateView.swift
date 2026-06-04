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

import Combine
import SwiftUI

// MARK: - NetworkReachabilityMonitor

/// SwiftUI-friendly bridge over the app's shared `DSReachabilityManager`.
///
/// Mirrors the UIKit `NetworkReachabilityHandling` protocol used by Coinbase screens,
/// but exposes the status as an `@Published` value so SwiftUI views can react to it.
/// Reuses the single shared reachability instance and its existing change notification
/// rather than creating a separate network monitor.
final class NetworkReachabilityMonitor: ObservableObject {
    @Published private(set) var networkStatus: NetworkStatus

    var isOnline: Bool { networkStatus == .online }

    private var observer: Any?
    private let reachability = DSReachabilityManager.shared()

    init() {
        if !reachability.isMonitoring {
            reachability.startMonitoring()
        }

        networkStatus = reachability.networkStatus

        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "org.dash.networking.reachability.change"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatus()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateStatus() {
        networkStatus = reachability.networkStatus
    }
}

// MARK: - NetworkUnavailableStateView

/// SwiftUI equivalent of Coinbase's `NetworkUnavailableView`.
/// Centered icon + title + subtitle, shown in place of network-dependent content while offline.
struct NetworkUnavailableStateView: View {
    private enum Layout {
        static let mainSpacing: CGFloat = 15
        static let textSpacing: CGFloat = 7
    }

    var body: some View {
        VStack(spacing: Layout.mainSpacing) {
            Image("network.unavailable")

            VStack(spacing: Layout.textSpacing) {
                Text(NSLocalizedString("Network Unavailable", comment: "Network Unavailable"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primaryText)

                Text(NSLocalizedString("Please check your network connection", comment: "Network Unavailable"))
                    .font(.footnote)
                    .foregroundColor(.secondaryText)
            }
            .multilineTextAlignment(.center)
        }
    }
}

#if DEBUG
#Preview {
    NetworkUnavailableStateView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground)
}
#endif
