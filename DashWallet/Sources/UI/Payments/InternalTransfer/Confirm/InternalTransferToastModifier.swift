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

import DashUIKit
import SwiftUI

extension View {
    /// Announces an internal transfer's progress on whichever surface the
    /// user is looking at.
    ///
    /// The confirm sheet no longer waits for the transfer — it hands off and
    /// closes — so nothing owned by the transfer is on screen when the outcome
    /// arrives. This is where it surfaces instead.
    func internalTransferToast(runner: InternalTransferRunner) -> some View {
        modifier(InternalTransferToastModifier(runner: runner))
    }
}

private struct InternalTransferToastModifier: ViewModifier {
    @ObservedObject var runner: InternalTransferRunner

    /// Long enough to read a failure reason, which is the only one that says
    /// something the history will not.
    private static let duration: TimeInterval = 3

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let notice = runner.notice {
                    DashUIKit.Toast(style: style(for: notice), message: message(for: notice))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: runner.notice)
            .task(id: runner.notice) {
                guard runner.notice != nil else { return }
                try? await Task.sleep(for: .seconds(Self.duration))
                // Cancelled when the notice changes or the view goes away, so
                // a later one restarts the countdown instead of being cut
                // short by the previous one.
                guard !Task.isCancelled else { return }
                runner.notice = nil
            }
    }

    private func style(for notice: InternalTransferRunner.Notice) -> ToastStyle {
        switch notice {
        case .started: return .loading
        case .busy: return .warning
        case .succeeded, .submitted: return .success
        case .failed: return .error
        }
    }

    private func message(for notice: InternalTransferRunner.Notice) -> String {
        switch notice {
        case .started:
            return NSLocalizedString(
                "Transfer started",
                comment: "Internal transfer handed to the background runner")
        case .busy:
            return NSLocalizedString(
                "Another transfer is still in progress",
                comment: "A second internal transfer was started before the first finished")
        case .succeeded:
            return NSLocalizedString(
                "Transfer complete",
                comment: "")
        case .submitted:
            return NSLocalizedString(
                "Transfer sent — waiting for the network to confirm it",
                comment: "Internal transfer accepted but not yet confirmed")
        case .failed(let reason):
            return reason
        }
    }
}
