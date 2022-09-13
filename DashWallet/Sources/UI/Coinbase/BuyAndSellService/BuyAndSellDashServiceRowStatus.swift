//
//  BuyAndSellDashServiceRowStatus.swift
//  Coinbase
//
//  Created by hadia on 06/09/2022.
//

import SwiftUI

struct BuyAndSellDashServiceRowStatus: View {
    var balance: String?
    var localBalance: String?
    var status : BuyAndSellDashServicesModel.ServiceStatus
    
    var body: some View {
        VStack(spacing:0){
            HStack(spacing:4) {
                if(status == BuyAndSellDashServicesModel.ServiceStatus.CONNECTED){
                    Image("Connected")
                    Text("Connected")
                        .frame(alignment: .leading)
                        .font(Font.custom("MontserratRegular", size: 10))
                        .padding(0)
                }else{
                    Image("Disconnected")
                    Text("Disconnected")
                        .frame(alignment: .leading)
                        .font(Font.custom("MontserratRegular", size: 10))
                        .padding(0)
                }
                
                HStack(spacing:0) {
                    if let  balance = balance  {
                        Image("dashCircleFilled")
                            .padding(4)
                        Text(balance)
                            .font(Font.custom("MontserratRegular", size: 10))
                            .padding(0)
                    }
                    
                    if let  localBalance = localBalance  {
                        Text(" = ")
                            .font(Font.custom("MontserratRegular", size: 10))
                            .padding(0)
                        
                        Text(localBalance)
                            .frame(alignment: .trailing)
                            .font(Font.custom("MontserratRegular", size: 10))
                            .padding(0)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .trailing)
            } .padding([.trailing,.leading,.top],  8)
            if(status == BuyAndSellDashServicesModel.ServiceStatus.DISCONNECTED){
                Text("Last known balance")
                    .frame(maxWidth: .infinity , alignment: .trailing)
                    .font(Font.custom("MontserratRegular", size: 10))
                    .padding([.trailing,.leading,.bottom],  8)
            }
        }
    }
}

struct BuyAndSellDashServiceRowStatus_Previews: PreviewProvider {
    static var previews: some View {
        BuyAndSellDashServiceRowStatus(balance:"0,97 Dash",localBalance:" 190,00 US$",status:  BuyAndSellDashServicesModel.ServiceStatus.CONNECTED)
    }
}
