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

struct SendIntro: View {
    var title: String
    var destination: String? = nil
    var balance: Double = 0.00
    var usdEquivalent: Double = 0.00

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            if let destination = destination {
                Text("to \(destination)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Balance: \(String(format: "%.2f", balance)) ")
                    .font(.body)
                + Text(Image(systemName: "bitcoinsign.circle"))
                + Text(" ~ \(String(format: "%.2f", usdEquivalent)) US$")
                    .font(.body)
                
                Button(action: {
                    // Action for the eye button
                }) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.gray)
                        .padding(5)
                        .background(Circle().fill(Color.gray.opacity(0.2)))
                }
            }
        }
        .padding()
    }
}
