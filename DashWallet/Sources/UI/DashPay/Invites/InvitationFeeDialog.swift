//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

public struct InvitationFeeDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedOption: FeeOption = .contested
    @State private var showConfirmation: Bool = false
    @State private var isConfirmed: Bool = false
    var action: () -> Void
    
    public var body: some View {
        BottomSheet(showBackButton: Binding<Bool>.constant(false)) {
            VStack(spacing: 0) {
                FeatureTopText(
                    title: NSLocalizedString("Invitation fee", comment: "Invites"),
                    text: NSLocalizedString("Each invitation will be funded so that the receiver can quickly create their username on the Dash Network.", comment: "Invites"),
                    alignment: .leading
                )
                
                VStack(spacing: 20) {
                    FeeOptionView(
                        isSelected: selectedOption == .contested,
                        title: NSLocalizedString("Contested", comment: "Usernames"),
                        amount: DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME,
                        description: NSLocalizedString("The person that you send this invitation to can request any username they want and the network will vote to approve it", comment: "Invites"),
                        onTap: { selectedOption = .contested }
                    )
                    
                    FeeOptionView(
                        isSelected: selectedOption == .nonContested,
                        title: NSLocalizedString("Non-contested", comment: "Usernames"),
                        amount: DWDP_MIN_BALANCE_TO_CREATE_USERNAME,
                        description: NSLocalizedString("The person that you send this invitation to can request a username that has a number 2-9, is more than 20 characters or that has a hyphen", comment: "Invites"),
                        onTap: { selectedOption = .nonContested }
                    )
                }
                .padding(.top, 40)
                
                Spacer()
                
                DashButton(
                    text: NSLocalizedString("Confirm and pay", comment: "Invites"),
                    style: .filled,
                    action: {
                        showConfirmation = true
                    }
                )
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
            .sheet(isPresented: $showConfirmation, onDismiss: {
                if isConfirmed {
                    action()
                }
            }) {
                let amount = selectedOption == .contested ?
                    Int64(DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME) : 
                    Int64(DWDP_MIN_BALANCE_TO_CREATE_USERNAME)
                
                let dialog = ConfirmSpendDialog(
                    amount: amount,
                    title: NSLocalizedString("Confirm invitation", comment: "Invites"),
                    onCancel: {
                        presentationMode.wrappedValue.dismiss()
                    },
                    onConfirm: {
                        isConfirmed = true
                        presentationMode.wrappedValue.dismiss()
                    }
                )
                
                if #available(iOS 16.0, *) {
                    dialog.presentationDetents([.height(240)])
                } else {
                    dialog
                }
            }
        }
    }
}

enum FeeOption {
    case contested
    case nonContested
}

struct FeeOptionView: View {
    let isSelected: Bool
    let title: String
    let amount: UInt64
    let description: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primaryText)
                    
                    Spacer()
                    
                    DashAmount(amount: Int64(amount), showDirection: false)
                }
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Color.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.dashBlue.opacity(0.04) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? Color.dashBlue : Color.primaryText.opacity(0.08),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
