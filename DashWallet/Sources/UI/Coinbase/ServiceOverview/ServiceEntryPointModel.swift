//
//  ServiceOverviewScreenModel.swift
//  Coinbase
//
//  Created by hadia on 27/09/2022.
//

import AuthenticationServices
import Foundation

// MARK: - ServiceOverviewScreenModelDelegate

protocol ServiceOverviewScreenModelDelegate: AnyObject {
    func didSignIn()
    func signInDidFail(error: Error)
}

// MARK: - ServiceOverviewScreenModel

@MainActor
class ServiceOverviewScreenModel {
    weak var delegate: ServiceOverviewScreenModelDelegate?

    var serviceType: Service

    init(serviceType: Service) {
        self.serviceType = serviceType
    }

    public func initiateCoinbaseAuthorization(with context: ASWebAuthenticationPresentationContextProviding) {
        Task { [weak self] in
            do {
                try await Coinbase.shared.signIn(with: context)
                self?.delegate?.didSignIn()
            } catch {
                self?.delegate?.signInDidFail(error: error)
            }
        }
    }

}

extension Service {

    var supportedFeatures: [SupportedFeature] {
        switch self {
        case .coinbase: return [
                SupportedFeature(serviceName:String(localized: "Buy Dash with fiat", comment: "Dash Service Overview"),
                                 imageName:"service.BuyDashwithfiat"),

// Disable per MO-103
//                SupportedFeature(serviceName:NSLocalizedString("Buy and convert Dash with another crypto",
//                                                               comment: "Dash Service Overview"),
//                                 imageName:"service.BuyAndConvertDash"),

                SupportedFeature(serviceName:String(localized: "Transfer Dash", comment: "Dash Service Overview"),
                                 imageName:"service.TransferDash",
                                 serviceSubtitle: String(localized: "Between Dash Wallet and your Coinbase account",
                                                                    comment: "Dash Service Overview")),
            ]

        case .uphold: return [
                SupportedFeature(serviceName:String(localized: "Transfer Dash", comment: "Dash Service Overview"),
                                 imageName:"service.TransferDash",
                                 serviceSubtitle: String(localized: "From Uphold to your Dash Wallet",
                                                                    comment: "Dash Service Overview")),
            ]
            
        case .topper: return []
        case .maya: return []
        case .swapKit: return []
        }
    }

    var entryTitle: String {
        switch self {
        case .coinbase: return String(localized: "Link your Coinbase account", comment: "Dash Service Overview")
        case .uphold: return String(localized: "Link your Uphold account", comment: "Dash Service Overview")
        case .topper: return ""
        case .maya: return ""
        case .swapKit: return ""
        }
    }

    var entryIcon: String {
        switch self {
        case .coinbase: return "service.coinbase.square"
        case .uphold: return "uphold_logo"
        case .topper: return "portal.topper"
        case .maya: return "portal.maya"
        case .swapKit: return "menu-swapkit"
        }
    }

    var serviceButtonTitle: String {
        switch self {
        case .coinbase: return String(localized: "Link Coinbase Account", comment: "Dash Service Overview")
        case .uphold: return String(localized: "Link Uphold account", comment: "Dash Service Overview")
        case .topper: return ""
        case .maya: return ""
        case .swapKit: return ""
        }
    }
}


// MARK: - SupportedFeature

struct SupportedFeature {
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
