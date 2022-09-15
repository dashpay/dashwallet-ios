//
//  BuyAndSellDashServiceList.swift
//  Coinbase
//
//  Created by hadia on 06/09/2022.
//

import SwiftUI


struct BuyAndSellDashServiceList: View {
    @StateObject
    private var viewModel = BuyAndSellSrviceViewmodel()
    
    var dismiss: () -> Void = {}
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    @State var isCoinbaseTapped = false
    
    var body: some View {
        NavigationView {
            
            VStack(alignment: .leading
                   , spacing:0){
                
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Image("backarrow") // set image here
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                }
                .frame(alignment: Alignment.topLeading)
                .padding(.all, 12)
                
                List {
                    ForEach(viewModel.buyAndSellDashServicesList, id: \.id) { buyAndSellDashServicesModel in
                        ZStack {
                            NavigationLink(destination: CoinbasePortalView(),isActive: $isCoinbaseTapped
                            ){
                                EmptyView()
                            }.buttonStyle(PlainButtonStyle())
                            
                            BuyAndSellDashServiceRow(buyAndSellDashServicesModel: buyAndSellDashServicesModel)
                                .listRowInsets(.init(top:10, leading: 0, bottom: 10, trailing: 0))
                                .listRowBackground(Color.clear)
                                .onTapGesture(perform: {
                                    if(buyAndSellDashServicesModel.serviceType == .COINBASE){
                                        if(!viewModel.isConnected || viewModel.showUserNeedDashWallet){
                                            viewModel.signInTapped()
                                        }else{
                                            isCoinbaseTapped = true
                                        }
                                    }
                                })
                            
                        }
                    }
                }.onAppear {
                    viewModel.checkServiceStatus()
                }
            }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity,alignment: .topLeading)
                .background(Color.screenBackgroundColor)
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
                .edgesIgnoringSafeArea(.bottom)
            
        }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity,alignment: .topLeading)
            .background(Color.screenBackgroundColor)
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .edgesIgnoringSafeArea(.bottom)
            .alert(isPresented: $viewModel.showUserNeedDashWallet) {
                Alert(
                    title: Text("You should create your Coinbase account outside the Dash Pay app"),
                    message: Text("After you create your Coinbase account go back to the Dash Pay app and sign in"),
                    dismissButton: .default(Text("Close"))
                )
            }
        
    }
}

struct BuyAndSellDashServiceList_Previews: PreviewProvider {
    static var previews: some View {
        BuyAndSellDashServiceList()
    }
}
