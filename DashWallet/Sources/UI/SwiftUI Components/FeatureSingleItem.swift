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

struct FeatureSingleItem: View {
    let iconName: IconName
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Icon(name: iconName)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primaryText)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondaryText)
            }
            .padding(.top, 10)
        }
    }
}

// Preview
struct FeatureSingleItem_Previews: PreviewProvider {
    static var previews: some View {
        FeatureSingleItem(
            iconName: .system("person.circle"),
            title: "Create a username",
            description: "Pay to usernames. No more alphanumeric addresses."
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
