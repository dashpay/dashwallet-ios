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

struct DashSwitch: View {

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
              .foregroundColor(.clear)
              .frame(width: 39, height: 24)
              .background(Color.white)
              .cornerRadius(1000)
              .shadow(color: Color(red: 0.1, green: 0.13, blue: 0.15).opacity(0.06), radius: 1, x: 0, y: 1)
              .shadow(color: Color(red: 0.1, green: 0.13, blue: 0.15).opacity(0.1), radius: 1.5, x: 0, y: 1)
        }
        .padding(2)
        .frame(width: 64, alignment: .leading)
        .background(Color.gray300Alpha50)
        .cornerRadius(1000)
    }
}

#Preview {
    DashSwitch()
}
