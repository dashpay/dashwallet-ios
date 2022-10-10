//
//  ServiceOverviewScreenModel.swift
//  Coinbase
//
//  Created by hadia on 27/09/2022.
//

import Foundation

struct ServiceOverviewScreenModel:Hashable, Identifiable {
    var id: Int
    var serviceType: ServiceType
    var serviceName: String
    var serviceButtonTitle: String
    var imageName: String
    var supportedFeatures: [SupportedFeature]
    
    public enum ServiceType :Codable{
        case COINBASE
        case Uphold
    }
}

struct SupportedFeature :Hashable, Identifiable {
    var id: Int
    var serviceName: String
    var imageName: String
    var serviceSubtitle: String?
}

extension ServiceOverviewScreenModel {
    static var getCoinbaseServiceEnteryPoint =
    ServiceOverviewScreenModel(id: 1, serviceType:ServiceType.COINBASE, serviceName: "Link your Coinbase account", serviceButtonTitle: "Link Coinbase Account", imageName: "Coinbase_square",
                                 supportedFeatures: [    SupportedFeature(id:0,
                                                                          serviceName:"Buy Dash with fiat",
                                                                          imageName:"BuyDashwithfiat"),
                                                         SupportedFeature(id:1,
                                                                          serviceName:"Buy and convert Dash with another crypto",
                                                                          imageName:"BuyAndConvertDash"),
                                                         SupportedFeature(id:2,
                                                                          serviceName:"Transfer Dash",
                                                                          imageName:"TransferDash",
                                                                          serviceSubtitle: "Between Dash Wallet and your Coinbase account")])
    
    
    static var getUpholdServiceEnteryPoint =
    ServiceOverviewScreenModel(id: 2,serviceType:ServiceType.Uphold, serviceName: "Link your Uphold account", serviceButtonTitle: "Link your Uphold account", imageName: "Uphold",
                                 supportedFeatures: [
                                    SupportedFeature(id:3,
                                                     serviceName:"Transfer Dash",
                                                     imageName:"TransferDash",
                                                     serviceSubtitle: "From Uphold to your Dash Wallet")])
    
}
