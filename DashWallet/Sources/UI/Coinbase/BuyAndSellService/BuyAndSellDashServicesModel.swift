//
//  BuyAndSellDashServicesModel.swift
//  Coinbase
//
//  Created by hadia on 04/09/2022.
//

import Foundation

// MARK: - AddressInfo
struct BuyAndSellDashServicesModel:Hashable, Identifiable {
    var id: Int
    var serviceType: ServiceType
    var serviceStatus: ServiceStatus
    var serviceName: String
    var balance: String?
    var localBalance: String?
    var imageName: String
    
    public enum ServiceStatus :Codable{
        case CONNECTED
        case DISCONNECTED
        case IDLE
        
    }
    
    public enum ServiceType :Codable{
        case COINBASE
    }
}


extension BuyAndSellDashServicesModel {
    static var getBuyAndSellDashServicesList = [
        BuyAndSellDashServicesModel(id: 1, serviceType:ServiceType.COINBASE,
                                    serviceStatus: ServiceStatus.IDLE, serviceName: "Coinbase", imageName: "Coinbase")
    ]
    
    static var getBuyAndSellDashServicesListExample = [
        BuyAndSellDashServicesModel(id: 1, serviceType:ServiceType.COINBASE,
                                    serviceStatus: ServiceStatus.IDLE, serviceName: "Coinbase", imageName: "Coinbase"),
        BuyAndSellDashServicesModel(id: 2, serviceType:ServiceType.COINBASE,
                                    serviceStatus: ServiceStatus.CONNECTED, serviceName: "Coinbase",balance:"0,97 Dash",localBalance:" 190,00 US$", imageName: "Coinbase"),
        BuyAndSellDashServicesModel(id: 3, serviceType:ServiceType.COINBASE,
                                    serviceStatus: ServiceStatus.DISCONNECTED,serviceName: "Coinbase",balance:"0,97 Dash",localBalance:" 190,00 US$", imageName: "Coinbase")
    ]
}


