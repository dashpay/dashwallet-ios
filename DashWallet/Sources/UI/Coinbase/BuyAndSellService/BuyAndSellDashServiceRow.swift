//
//  BuyAndSellDashServiceRow.swift
//  Coinbase
//
//  Created by hadia on 06/09/2022.
//

import SwiftUI

struct BuyAndSellDashServiceRow: View {
    var buyAndSellDashServicesModel : BuyAndSellDashServicesModel
    var body: some View {
        HStack(spacing: 0){
            VStack(spacing: 0){
                
                HStack(alignment: .center, spacing: 0) {
                    Image(buyAndSellDashServicesModel.imageName)
                    
                    Text(LocalizedStringKey(buyAndSellDashServicesModel.serviceName))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(Font.custom("MontserratSemiBold", size: 14))
                        .padding(10)
                    
                    
                    Image("greyarrow")
                    
                }.padding(10)
                
                if(buyAndSellDashServicesModel.serviceStatus != .IDLE){
                    Divider()
                        .padding(.horizontal,8)
                }
                
                
                if(buyAndSellDashServicesModel.serviceStatus == .CONNECTED || buyAndSellDashServicesModel.serviceStatus == .DISCONNECTED){
                    
                    BuyAndSellDashServiceRowStatus(balance:buyAndSellDashServicesModel.balance,
                                                   localBalance:buyAndSellDashServicesModel.localBalance,
                                                   status: buyAndSellDashServicesModel.serviceStatus)
                    
                }
                
            }
            .background(Color.white)
            .cornerRadius(10)
        }
    }
}

struct BuyAndSellDashServiceRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BuyAndSellDashServiceRow(buyAndSellDashServicesModel: BuyAndSellDashServicesModel.getBuyAndSellDashServicesListExample[0])
            
            BuyAndSellDashServiceRow(buyAndSellDashServicesModel: BuyAndSellDashServicesModel.getBuyAndSellDashServicesListExample[1])
            
            BuyAndSellDashServiceRow(buyAndSellDashServicesModel: BuyAndSellDashServicesModel.getBuyAndSellDashServicesListExample[2])
        } .previewLayout(.fixed(width: 300, height: 100))
        
    }
}
