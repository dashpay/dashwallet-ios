//
//  ServiceOverviewViewController.swift
//  Coinbase
//
//  Created by hadia on 28/09/2022.
//

import Foundation
import UIKit
import SwiftUI
import AuthenticationServices


protocol ServiceOverviewDelegate : AnyObject {
    func presentCompletedCoinbaseViewController()
    func presentCompletedUpholdViewController()
    
}

class ServiceOverviewViewController:  UIViewController, UITableViewDelegate, UITableViewDataSource  {
    @IBOutlet weak var serviceIcon: UIImageView!
    @IBOutlet weak var serviceHint: UILabel!
    @IBOutlet weak var serviceLinkButton: UIButton!
    @IBOutlet weak var serviceFeaturesTables: UITableView!
    
    weak var delegate: ServiceOverviewDelegate?
    
    var model: ServiceOverviewScreenModel = ServiceOverviewScreenModel.getCoinbaseServiceEnteryPoint
    
    @IBAction func actionHandler() {
        model.initiateCoinbaseAuthorization(with: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        super.viewWillAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        if let nc = navigationController, nc.viewControllers.count > 2 {
            nc.viewControllers = nc.viewControllers.filter { $0 != self }
        }
        
        super.viewDidDisappear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        model.delegate = self
        setupHeaderAndTitleLabel()
        
        serviceLinkButton.setTitle(model.serviceType.self.serviceButtonTitle, for: .normal)
    }
    
    override func loadView() {
        super.loadView()
        setupTableView()
    }
    
    func setupHeaderAndTitleLabel() {
        serviceIcon?.image = UIImage(named: model.serviceType.entryIcon)
        serviceHint.text = model.serviceType.entryTitle
    }
    
    func setupTableView() {
        serviceFeaturesTables.allowsSelection = false
        serviceFeaturesTables.delegate = self
        serviceFeaturesTables.dataSource = self
        serviceFeaturesTables.separatorStyle = UITableViewCell.SeparatorStyle.none
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.serviceType.self.supportedFeatures.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "serviceOverviewTableCell", for: indexPath) as? ServiceOverviewTableCell {
            let supportedFeature = model.serviceType.self.supportedFeatures[indexPath.row]
            cell.selectionStyle = .none
            cell.updateCellView(supportedFeature: supportedFeature)
            return cell
        }
        else {
            return ServiceOverviewTableCell()
        }
    }
    
    @objc class func controller() -> ServiceOverviewViewController {
        return vc(ServiceOverviewViewController.self, from: sb("Coinbase"))
    }
}

extension ServiceOverviewViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return view.window!
    }
}

extension ServiceOverviewViewController: ServiceOverviewScreenModelDelegate {
    func didSignIn() {
        let vc = UIHostingController(rootView: CoinbasePortalView())
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func signInDidFail(error: Error) {
        navigationController?.popViewController(animated: true)
    }
}
