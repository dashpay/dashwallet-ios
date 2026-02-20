//
//  Created by Claude
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

struct ShortcutSelectionView: View {
    let onSelect: (ShortcutActionType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(ShortcutActionType.customizableActions, id: \.rawValue) { actionType in
                Button {
                    onSelect(actionType)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(uiImage: actionType.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                        Text(actionType.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(.dw_darkTitle()))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle(NSLocalizedString("Select option", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
