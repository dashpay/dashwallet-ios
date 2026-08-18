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

import SwiftUI
import DashUIKit

/// What Advanced mode does, shown when the settings row's info glyph is tapped.
///
/// Self-sizing on purpose: the copy is expected to grow as the mode gains the
/// surfaces it gates, and `BottomSheet.selfSizing` pairs `fillsHeight: false`
/// with the sizing modifier so the sheet keeps snapping to it without anything
/// here being re-tuned.
struct AdvancedModeInfoSheet: View {
    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Advanced mode", comment: "Settings"),
            showBackButton: .constant(false)
        ) {
            // TODO(advanced-mode): the copy lands here once the surfaces the
            // flag gates are decided. Until then this says only what is true of
            // the build it ships in.
            Text(NSLocalizedString(
                "Reveals extra wallet details and actions intended for experienced users. Turning it off hides them again; nothing about your funds changes either way.",
                comment: "Settings"))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }
}

#if DEBUG

#Preview {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            AdvancedModeInfoSheet()
        }
}

#endif
