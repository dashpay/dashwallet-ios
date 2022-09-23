//
//  Created by hadia
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

struct CoinabaseConnectionStatusToolbar : View {
    var isConnected: Bool = true
    
    var body: some View {
        
        HStack(alignment: .center ){
            Image( "Coinbase")
            
            VStack(spacing: 0 ) {
                Text(LocalizedStringKey("Coinbase")).font(Font.custom("MontserratSemiBold", size: 16))
                
                HStack(spacing:4) {
                    if(isConnected){
                        Image("Connected")
                        Text( "Connected").font(Font.custom("MontserratRegular", size: 10))
                    }else{
                        Image("Disconnected")
                        Text("Disconnected").font(Font.custom("MontserratRegular", size: 10))
                    }
                    
                }
            }}.frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
        
    }
}

struct CoinabaseToolbar_Previews: PreviewProvider {
    static var previews: some View {
        CoinabaseConnectionStatusToolbar(isConnected: true)
        CoinabaseConnectionStatusToolbar(isConnected: false)
    }
}
