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
import Lottie

struct CoinJoinProgressView: View {
    @State var state: MixingStatus
    @State var progress: Double
    @State var mixed: Double
    @State var total: Double
    var showBalance: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if state == .mixing {
                LottieView(animation: .named("mixing_anim"))
                    .looping()
                    .frame(width: 34, height: 34)
            } else {
                LottieView(animation: .named("mixing_anim"))
                    .currentProgress(1)
                    .frame(width: 34, height: 34)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                CoinJoinProgressInfo(
                    state: state,
                    progress: progress,
                    mixed: mixed,
                    total: total,
                    showBalance: showBalance,
                    textColor: .primaryText,
                    font: .subheadline
                ).padding(.leading, -4)
                
                SwiftUI.ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .dashBlue))
                    .frame(height: 6)
                    .padding(.top, 2)
            }
            .padding(.leading, 5)
        }
        .padding(12)
        .background(Color.secondaryBackground)
        .cornerRadius(8)
    }
}

struct CoinJoinProgressInfo: View {
    @State var state: MixingStatus
    @State var progress: Double
    @State var mixed: Double
    @State var total: Double
    var showBalance: Bool
    var textColor: Color
    var font: Font
    
    var body: some View {
        HStack(spacing: 0) {
            Text(state.localizedValue)
                .foregroundColor(textColor)
                .font(font)
                .padding(.leading, state == .mixing ? 2 : 5)
            
            if state.isInProgress {
                if state != .finishing {
                    Text(progress.formatted(.percent.precision(.fractionLength(0...1))))
                        .foregroundColor(textColor)
                        .font(font)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                if showBalance {
                    Text("\(mixed, format: .number.precision(.fractionLength(0...3))) of \(total, format: .number.precision(.fractionLength(0...3)))")
                        .foregroundColor(textColor)
                        .font(font)
                    
                    Image("icon_dash_currency")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: font.pointSize, height: font.pointSize)
                        .padding(.leading, 2)
                        .foregroundColor(textColor)
                } else {
                    Text("****")
                        .foregroundColor(textColor)
                        .font(font)
                }
            }
        }
    }
}

#Preview {
    CoinJoinProgressView(state: .mixing, progress: 0.45, mixed: 0.123, total: 0.321, showBalance: true)
}
