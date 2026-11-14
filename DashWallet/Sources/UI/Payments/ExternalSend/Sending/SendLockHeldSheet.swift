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

/// The sheet a `lockHeld` send opens: the money is held in an asset lock whose Platform step did not finish. Finish
/// runs the ViewModel's resume; Close leaves the lock for the transaction details. Neither closes it while Finish runs.
struct SendLockHeldSheet: View {
    @ObservedObject var viewModel: SendLockHeldViewModel
    let onClose: () -> Void

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: viewModel.title,
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!viewModel.isFinishing),
            showsCloseButton: false,
            onClose: onClose,
            content: {
                ViewThatFits(in: .vertical) {
                    sheetBody
                    ScrollView { sheetBody }
                }
            })
    }

    private var sheetBody: some View {
        VStack(spacing: 16) {
            if viewModel.state == .failed {
                ErrorIllustration()
            }
            Text(viewModel.message)
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = viewModel.failureMessage {
                DashUIKit.SystemMessageView(
                    title: failure,
                    icon: DashIcon.SystemMessage.infoRectSmall.source,
                    backgroundColor: Color.dash.blueAlpha5)
                    .accessibilityIdentifier("send_lock_held_failure")
            }
            HStack(spacing: 8) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Close", comment: "External send"),
                    isEnabled: !viewModel.isFinishing,
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onClose)
                    .accessibilityIdentifier("send_lock_held_close")
                DashUIKit.DashButton(
                    text: NSLocalizedString("Finish", comment: "External send"),
                    isEnabled: !viewModel.isFinishing,
                    isLoading: viewModel.isFinishing,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: { Task { await viewModel.finish() } })
                    .accessibilityIdentifier("send_lock_held_finish")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

#if DEBUG

private struct PreviewResumer: HeldAssetLockResuming {
    func resume(_ lock: HeldAssetLock) async throws -> AssetLockRecoveryService.Outcome { .completed }
}

@MainActor
private func previewSheet(_ state: SendLockHeldViewModel.State) -> some View {
    let lock = HeldAssetLock(fundingTypeRaw: 4, txidWire: Data(repeating: 0xAB, count: 32), vout: 0)
    let viewModel = SendLockHeldViewModel(lock: lock, resumer: PreviewResumer(), state: state)
    return Color.dash.primaryBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { SendLockHeldSheet(viewModel: viewModel, onClose: {}) }
}

#Preview("Ready") { previewSheet(.ready) }

#Preview("Finishing") { previewSheet(.finishing) }

#Preview("Failed") { previewSheet(.failed) }

#Preview("Failed, large Dynamic Type") {
    previewSheet(.failed)
        .dynamicTypeSize(.accessibility3)
}

#endif
