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

import Foundation
import SwiftUI

struct OkItem: Identifiable {
    let id = UUID()
    let name: String
}

struct SectionData: Identifiable {
    let id = UUID()
    let title: String
    let items: [OkItem]
}


let sections: [SectionData] = [
    SectionData(title: "Fruits", items: [
        OkItem(name: "Apple"),
        OkItem(name: "Banana"),
        OkItem(name: "Orange")
    ]),
    SectionData(title: "Vegetables", items: [
        OkItem(name: "Carrot"),
        OkItem(name: "Broccoli"),
        OkItem(name: "Spinach")
    ]),
    SectionData(title: "Dairy", items: [
        OkItem(name: "Milk"),
        OkItem(name: "Cheese"),
        OkItem(name: "Yogurt")
    ])
]


struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                ForEach(sections) { section in
                    Section(header: Text(section.title)
                                .font(.headline)
                                .padding(.leading, -20) // Adjust padding as needed
                                .frame(maxWidth: .infinity, alignment: .leading)
                    ) {
                        ForEach(section.items) { item in
                            Text(item.name)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationTitle("Grouped List")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
