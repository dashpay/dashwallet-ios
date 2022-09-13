//
//  CoinbaseServiceItem.swift
//  Coinbase
//
//  Created by hadia on 21/06/2022.
//

import SwiftUI

struct CoinbaseServiceItem: View {
    
    var imageName: String
    var title: String
    var subTitle: String?
    var showDivider:Bool = false
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 0){
            Image(imageName).padding(14)
            VStack(alignment: .leading, spacing: 0){
            
                let titleView = Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(Font.custom("MontserratSemiBold", size: 14))
                    
                if let subTitle = subTitle {
                    titleView
                    Text(subTitle).font(Font.custom("MontserratRegular", size: 12)) .padding(.bottom, 11)
                   
                }else{
                    titleView .padding(.bottom, 11)
                }
                if(showDivider){
                  Divider()
                }
              
            } .frame(maxWidth: .infinity)
            .padding(.top, 11)
        }
        
    }
}

struct CoinbaseServiceItem_Previews: PreviewProvider {
    static var previews: some View {
        CoinbaseServiceItem(imageName: "Coinbase",title: "Buy Dash",subTitle: "Receive directly into Dash Wallet.")
        CoinbaseServiceItem(imageName: "Coinbase",title: "Buy Dash",subTitle: nil)
    }
}
