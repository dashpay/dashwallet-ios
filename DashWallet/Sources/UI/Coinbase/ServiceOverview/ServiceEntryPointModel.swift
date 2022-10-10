//
//  ServiceOverviewScreenModel.swift
//  Coinbase
//
//  Created by hadia on 27/09/2022.
//

import Foundation

struct ServiceOverviewScreenModel {
    var serviceType: Service
    
    public enum Service :CaseIterable{
        case coinbase
        case uphold
    }
}

extension ServiceOverviewScreenModel.Service {
    
    var supportedFeatures: [SupportedFeature] {
        switch self {
        case .coinbase: return  [
            SupportedFeature(
                serviceName:NSLocalizedString("Buy Dash with fiat", comment: "Dash Service Overview"),
                imageName:"service.BuyDashwithfiat"),
           
            SupportedFeature(
                serviceName:NSLocalizedString("Buy and convert Dash with another crypto", comment: "Dash Service Overview"),
                imageName:"service.BuyAndConvertDash"),
            
            SupportedFeature(
                serviceName:NSLocalizedString("Transfer Dash", comment: "Dash Service Overview"),
                imageName:"service.TransferDash",
                serviceSubtitle: NSLocalizedString("Between Dash Wallet and your Coinbase account", comment: "Dash Service Overview"))]
      
        case .uphold: return  [
            SupportedFeature(
                serviceName:NSLocalizedString("Transfer Dash", comment: "Dash Service Overview"),
                imageName:"service.TransferDash",
                serviceSubtitle: NSLocalizedString("From Uphold to your Dash Wallet", comment: "Dash Service Overview"))]
        }
    }
    
    var title: String {
        switch self {
        case .coinbase: return NSLocalizedString("Link your Coinbase account", comment: "Dash Service Overview")
        case .uphold: return NSLocalizedString("Link your Uphold account", comment: "Dash Service Overview")
        }
    }
    
    var icon: String {
        switch self {
        case .coinbase: return "service.coinbase.square"
        case .uphold: return "service.uphold.square"
        }
    }
    
    var serviceButtonTitle: String {
        switch self {
        case .coinbase: return NSLocalizedString("Link Coinbase Account", comment: "Dash Service Overview")
        case .uphold: return NSLocalizedString("Link Uphold account", comment: "Dash Service Overview")
        }
    }
}


struct SupportedFeature{
    var serviceName: String
    var imageName: String
    var serviceSubtitle: String?
}

extension ServiceOverviewScreenModel {
    static var getCoinbaseServiceEnteryPoint =
    ServiceOverviewScreenModel(serviceType:Service.coinbase)
    
    static var getUpholdServiceEnteryPoint =
    ServiceOverviewScreenModel(serviceType:Service.uphold)
    
}
