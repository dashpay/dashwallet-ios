//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

public struct VerifyIdentityScreen: View {
    let username: String
    var action: () -> Void
    
    public var body: some View {
        VStack {
            Text(NSLocalizedString("Verify your identity", comment: "Usernames"))
            Text(NSLocalizedString("The link you send will be visible only to the network owners", comment: "Usernames"))
            
            Spacer()

            HStack {
                Text("Please vote to approve my requested Dash username - \(username)")
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Button(action: {
                    UIPasteboard.general.string = "Please vote to approve my requested Dash username - \(username)"
                }) {
                    Image(systemName: "doc.on.doc")
                        .padding(8)
                }
            }
            .padding()
        }
    }
}
