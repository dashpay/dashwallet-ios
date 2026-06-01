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
    let usedTypes: Set<ShortcutActionType>
    let onSelect: (ShortcutActionType) -> Void
    @Environment(\.dismiss)
    private var dismiss

    private var availableActions: [ShortcutActionType] {
        ShortcutActionType.customizableActions.filter { !usedTypes.contains($0) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                if availableActions.isEmpty {
                    Text(NSLocalizedString("All shortcuts are already in use", comment: "Shortcut selection empty state"))
                        .font(.subheadline)
                        .foregroundColor(.secondaryText)
                        .padding(.vertical, 16)
                } else {
                    ForEach(availableActions, id: \.rawValue) { actionType in
                        MenuItem(
                            title: actionType.title,
                            icon: .custom(actionType.iconName),
                            action: {
                                onSelect(actionType)
                                dismiss()
                            }
                        )
                    }
                }
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 20))
            .padding(.top, 10)
            .padding(.horizontal, 20)
        }
    }
}

#if DEBUG
#Preview("All available") {
    ShortcutSelectionView(usedTypes: []) { _ in }
}

#Preview("Filtered – receive & send used") {
    ShortcutSelectionView(usedTypes: [.receive, .send]) { _ in }
}

#Preview("All used (empty state)") {
    ShortcutSelectionView(usedTypes: Set(ShortcutActionType.customizableActions)) { _ in }
}

#Preview("Bottom sheet") {
    VStack {
        Color.secondaryBackground.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                let sheet = BottomSheet(title: NSLocalizedString("Select option", comment: ""), showBackButton: .constant(false)) {
                    ShortcutSelectionView(usedTypes: [.receive, .send, .spend]) { _ in }
                }

                if #available(iOS 16.4, *) {
                    sheet
                        .presentationDetents([.large])
                        .presentationBackground(Color.primaryBackground)
                        .presentationCornerRadius(32)
                        .presentationDragIndicator(.hidden)
                } else {
                    sheet
                }
            }
    }
}
#endif
