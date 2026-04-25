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

@available(iOS 14, *)
public struct ScrollViewWithOnScrollChanged<Content:View>: View {

    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let onScrollChanged: (_ origin: CGPoint) -> ()
    @State private var coordinateSpaceID: String = UUID().uuidString

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = false,
        @ViewBuilder content: () -> Content,
        onScrollChanged: @escaping (_ origin: CGPoint) -> ()) {
            self.axes = axes
            self.showsIndicators = showsIndicators
            self.content = content()
            self.onScrollChanged = onScrollChanged
        }

    public var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            LocationReader(coordinateSpace: .named(coordinateSpaceID), onChange: onScrollChanged)
            content
        }
        .coordinateSpace(name: coordinateSpaceID)
    }
}

@available(iOS 14, *)
struct ScrollViewWithOnScrollChanged_Previews: PreviewProvider {

    struct PreviewView: View {

        @State private var yPosition: CGFloat = 0

        var body: some View {
            ScrollViewWithOnScrollChanged {
                VStack {
                    ForEach(0..<30) { x in
                        Text("x: \(x)")
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .cornerRadius(10)
                            .background(Color.red)
                            .padding()
                            .id(x)
                    }
                }
            } onScrollChanged: { origin in
                yPosition = origin.y
            }
            .overlay(Text("Offset: \(yPosition)"))
        }
    }

    static var previews: some View {
        PreviewView()
    }
}
