//
//  CSVExportSheet.swift
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

import SwiftUI

struct CSVExportSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(colorScheme == .dark ? Color.whiteAlpha20 : Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 6)

            // Close button
            NavBarClose {
                presentationMode.wrappedValue.dismiss()
            }

            // Content
            VStack(spacing: 0) {
                // Icon
                Image("csv-export-large")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 94, height: 100)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("The full transaction history will be exported as a CSV file", comment: ""))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.primaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString("All payments will be considered as an expense and all incoming transactions will be income.\nThe owner of this wallet is responsible for making any cost basis adjustments in their chosen tax reporting system.", comment: ""))
                        .font(.system(size: 15))
                        .foregroundColor(Color.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }

            Spacer()

            // Button
            VStack(spacing: 0) {
                DashButton(
                    text: NSLocalizedString("Export CSV", comment: ""),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: true,
                    action: {
                        presentationMode.wrappedValue.dismiss()
                        onExport()
                    }
                )
                .padding(.horizontal, 60)
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Color.secondaryBackground)
    }
}

struct CSVExportSheet_Previews: PreviewProvider {
    static var previews: some View {
        CSVExportSheet(onExport: {})
    }
}
