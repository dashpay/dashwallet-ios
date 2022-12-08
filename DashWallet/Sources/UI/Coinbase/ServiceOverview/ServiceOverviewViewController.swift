//
//  ServiceOverviewViewController.swift
//  Coinbase
//
//  Created by hadia on 28/09/2022.
//

import AuthenticationServices
import Foundation
import SwiftUI
import UIKit


// MARK: - ServiceOverviewDelegate

protocol ServiceOverviewDelegate : AnyObject {
    func presentCompletedCoinbaseViewController()
    func presentCompletedUpholdViewController()
}

// MARK: - ServiceOverviewViewController

class ServiceOverviewViewController: ActionButtonViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet var serviceIcon: UIImageView!
    @IBOutlet var serviceHint: UILabel!
    @IBOutlet var serviceFeaturesTables: UITableView!
    @IBOutlet var mainContentView: UIView!

    weak var delegate: ServiceOverviewDelegate?

    var model = ServiceOverviewScreenModel.getCoinbaseServiceEnteryPoint

    override var actionButtonTitle: String? {
        model.serviceType.serviceButtonTitle
    }

    override func actionButtonAction(sender: UIView) {
        showActivityIndicator()
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

        view.backgroundColor = .dw_secondaryBackground()
        model.delegate = self

        setupContentView(mainContentView)
        setupHeaderAndTitleLabel()
        setupTableView()

        actionButton?.isEnabled = true
    }

    func setupHeaderAndTitleLabel() {
        serviceIcon?.image = UIImage(named: model.serviceType.entryIcon)
        serviceHint.text = model.serviceType.entryTitle
    }

    func setupTableView() {
        serviceFeaturesTables.estimatedRowHeight = 80
        serviceFeaturesTables.rowHeight = UITableView.automaticDimension
        serviceFeaturesTables.allowsSelection = false
        serviceFeaturesTables.separatorStyle = .none
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.serviceType.supportedFeatures.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "serviceOverviewTableCell",
                                                    for: indexPath) as? ServiceOverviewTableCell {
            let supportedFeature = model.serviceType.supportedFeatures[indexPath.row]
            cell.selectionStyle = .none
            cell.updateCellView(supportedFeature: supportedFeature)
            return cell
        }
        else {
            return ServiceOverviewTableCell()
        }
    }

    @objc class func controller() -> ServiceOverviewViewController {
        vc(ServiceOverviewViewController.self, from: sb("Coinbase"))
    }
}

// MARK: ASWebAuthenticationPresentationContextProviding

extension ServiceOverviewViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

// MARK: ServiceOverviewScreenModelDelegate

extension ServiceOverviewViewController: ServiceOverviewScreenModelDelegate {
    func didSignIn() {
        let vc = CoinbaseEntryPointViewController.controller()
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    func signInDidFail(error: Error) {
        navigationController?.popViewController(animated: true)
    }
}
