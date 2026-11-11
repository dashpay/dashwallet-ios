//
//  ConnectionsMessageDialog.swift
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

/// The disconnect question (SCR-03) and result (SCR-04) on Connections, as
/// DashUIKit's `ModalDialog`. The wording comes from the view model; this only
/// lays the message out: its paragraphs, and «Turn them off» / «Leave them»
/// for a question, «OK» otherwise. Every other Connections message shows here
/// too, with the warning icon unless it is a plain success.
enum ConnectionsMessageDialog {
    static func dialog(
        for message: ConnectionsScreenMessage,
        turnOff: @escaping (DAppConnection, DashConnectOfferedKeys) -> Void,
        dismiss: @escaping () -> Void
    ) -> ModalDialog {
        let paragraphs = message.text.components(separatedBy: "\n\n")
        let icon: ModalDialog.Icon? = message.kind == .success ? nil : .warning
        guard let connection = message.unrecordedKeysOf, let keys = message.unrecordedKeys else {
            return ModalDialog(
                icon: icon, heading: message.title, paragraphs: paragraphs,
                primaryAction: .init(title: NSLocalizedString("OK", comment: ""), handler: dismiss))
        }
        return ModalDialog(
            icon: icon, heading: message.title, paragraphs: paragraphs,
            primaryAction: .init(title: NSLocalizedString("Turn them off", comment: "DashConnect"), role: .destructive) {
                turnOff(connection, keys)
            },
            secondaryAction: .init(title: NSLocalizedString("Leave them", comment: "DashConnect"), handler: dismiss))
    }
}

// MARK: - Previews

private enum PreviewText {
    static let offered = "Disconnected. Keys this wallet did not record giving are still on your identity (2): keys of this app from "
        + "another device or from before a restore, or DashPay profile keys no connection holds. Turn them off too?"
    static let offeredNothingOff = "This wallet did not record giving the keys this app holds on your identity (2): they come from "
        + "another device, from before a restore, or are DashPay profile keys no connection holds. Turn them off?"
    static let notChecked = "This wallet could not tell yet which app holds some keys on your identity (1), so it left them on. Open Connections again later to check them."
    static let notAttributable = "Some keys on your identity (1) may belong to another app of the same developer, so this wallet left "
        + "them on. Each one shows on its own row in Connections; disconnect it there if you no longer need it."
    static let left = "Disconnected. Some keys of this app are still on your identity (1). Disconnect it again to turn them off."
    static let anotherIdentity = "This app has a key on another identity of this wallet. Switch to that identity to turn it off."
    static let error = "Could not disconnect: The network did not answer."
    static let busy = "Finish the request on screen, then disconnect the app again."
    static let purchased = "Token purchase completed."
}

private func dialogPreview(_ kind: ConnectionsScreenMessage.Kind, _ paragraphs: [String], offers: Bool = false) -> some View {
    let message = ConnectionsScreenMessage(
        kind: kind, text: paragraphs.joined(separator: "\n\n"),
        unrecordedKeysOf: offers ? MockDashConnectDataSource.sample(.active) : nil,
        unrecordedKeys: offers ? DashConnectOfferedKeys(identityId: Data(repeating: 1, count: 32), keyIds: [20, 21]) : nil)
    return ZStack {
        Color.dash.backgroundOverlay.ignoresSafeArea()
        ConnectionsMessageDialog.dialog(for: message, turnOff: { _, _ in }, dismiss: {})
            .padding(.horizontal, 20)
    }
}

#Preview("SCR-03 default") { dialogPreview(.question, [PreviewText.offered], offers: true) }
#Preview("SCR-03 nothing turned off") { dialogPreview(.question, [PreviewText.offeredNothingOff], offers: true) }
#Preview("SCR-03 with warnings") {
    dialogPreview(.question, [PreviewText.offered, PreviewText.notChecked, PreviewText.notAttributable], offers: true)
}
#Preview("SCR-04 not checked") { dialogPreview(.warning, [PreviewText.notChecked]) }
#Preview("SCR-04 not attributable") { dialogPreview(.warning, [PreviewText.notAttributable]) }
#Preview("SCR-04 left after question") { dialogPreview(.warning, [PreviewText.left]) }
#Preview("SCR-04 combined") {
    dialogPreview(.warning, [PreviewText.notChecked, PreviewText.notAttributable, PreviewText.left, PreviewText.anotherIdentity])
}
#Preview("SCR-04 another identity") { dialogPreview(.error, [PreviewText.anotherIdentity]) }
#Preview("SCR-04 error") { dialogPreview(.error, [PreviewText.error]) }
#Preview("SCR-04 busy") { dialogPreview(.error, [PreviewText.busy]) }
#Preview("Success, no icon") { dialogPreview(.success, [PreviewText.purchased]) }
#Preview("SCR-03 dark") {
    dialogPreview(.question, [PreviewText.offered, PreviewText.notAttributable], offers: true).preferredColorScheme(.dark)
}
