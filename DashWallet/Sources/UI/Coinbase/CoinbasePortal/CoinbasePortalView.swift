//
//  ContentView.swift
//  Coinbase
//
//  Created by hadia on 24/05/2022.
//

import SwiftUI


struct CoinbasePortalView: View {
    
    @StateObject
    private var viewModel = CoinbaseAccountViewmodel()
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    
    var body: some View {
        
        VStack(alignment: .center, spacing: 20) {
            VStack(alignment: .center, spacing: 0){
                let lastKnowBalance = viewModel.getLastKnownBalance()
                let dashBalance = viewModel.dashAccount?.balance.amount ?? lastKnowBalance ?? ""
                
                Text("Dash balance on Coinbase")
                    .font(Font.custom("MontserratRegular", size: 12))
                
                
                if (dashBalance != ""){
                    HStack{
                        Image("dashCurrency").padding(14)
                        Text(dashBalance)
                            .padding(.vertical, 5)
                            .font(Font.custom("MontserratMedium", size: 28))
                        
                        
                    }
                    if let fait = viewModel.getCoinbaseAccountFaitValue(balance: dashBalance){
                        Text(fait)
                            .font(Font.custom("MontserratRegular", size: 17))
                            .padding(.bottom, 20)
                    }
                    
                }
                
                VStack(alignment: .center, spacing: 0){
                    
                    NavigationLink(destination: TransferAmountView())
                    {                        CoinbaseServiceItem(imageName: "buyCoinbase",title: "Buy Dash",subTitle: "Receive directly into Dash Wallet.",showDivider: true)
                    }.buttonStyle(PlainButtonStyle())
                    
                    CoinbaseServiceItem(imageName: "sellDash",title: "Sell Dash",subTitle: "Receive directly into Coinbase.",showDivider: true)
                    CoinbaseServiceItem(imageName: "convertCrypto",title: "Convert Crypto",subTitle: "Between Dash Wallet and Coinbase.",showDivider: true)
                    CoinbaseServiceItem(imageName: "transferCoinbase",title: "Transfer Dash",subTitle: "Between Dash Wallet and Coinbase.")
                }
                .padding(.vertical, 5)
                .background(Color.white)
                .cornerRadius(10)
                
                Spacer()
                
                VStack(alignment: .center){
                    CoinbaseServiceItem(imageName: "logout",title: "Disconnect Coinbase Account")
                        .padding(.vertical, 5)
                        .background(Color.white)
                        .cornerRadius(10)
                }.frame( alignment: .bottom)
                    .onTapGesture(perform: {
                        viewModel.signOutTapped()
                        self.presentationMode.wrappedValue.dismiss()
                    }).padding(.bottom, 30)
                
            }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 15)
            
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CoinabaseConnectionStatusToolbar(isConnected: viewModel.isConnected)
                
//                HStack(alignment: .center ){
//                    Image( "Coinbase")
//
//                    VStack(spacing: 0 ) {
//                        Text(LocalizedStringKey("Coinbase")).font(Font.custom("MontserratSemiBold", size: 16))
//
//                        HStack(spacing:4) {
//                            if(viewModel.isConnected){
//                                Image("Connected")
//                                Text( "Connected").font(Font.custom("MontserratRegular", size: 10))
//                            }else{
//                                Image("Disconnected")
//                                Text("Disconnected").font(Font.custom("MontserratRegular", size: 10))
//                            }
//
//                        }.background( Color.clear)
//
//                    }}.frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            }
            
        }

        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity,alignment: .topLeading)
            .background(Color.screenBackgroundColor)
            .onAppear{
                viewModel.loadUserCoinbaseAccounts()
            }
    }
}

struct Previews_ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CoinbasePortalView()
    }
}
