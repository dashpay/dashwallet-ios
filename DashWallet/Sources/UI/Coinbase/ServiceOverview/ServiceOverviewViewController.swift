//
//  ServiceOverviewViewController.swift
//  Coinbase
//
//  Created by hadia on 28/09/2022.
//

import Foundation
import UIKit

class ServiceOverviewViewController:  UIViewController, UITableViewDelegate, UITableViewDataSource  {
    
    
    @IBOutlet weak var serviceIcon: UIImageView!
    @IBOutlet weak var serviceHint: UILabel!
    @IBOutlet weak var serviceLinkButton: UIButton!
    @IBOutlet weak var serviceFeaturesTables: UITableView!
    
    var serviceOverviewScreenModel:ServiceOverviewScreenModel = ServiceOverviewScreenModel.getCoinbaseServiceEnteryPoint
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeaderAndTitleLabel()
        
        serviceLinkButton.setTitle(serviceOverviewScreenModel.serviceButtonTitle, for: .normal)
    }
    
    override func loadView() {
        super.loadView()
        setupTableView()
    }
    
    func setupHeaderAndTitleLabel() {
        let serviceOverviewImage = UIImage(named: serviceOverviewScreenModel.imageName)
        serviceIcon?.image = serviceOverviewImage
        serviceHint.text = serviceOverviewScreenModel.serviceName
    }
    
    func setupTableView() {
        //assign tableview delegate and datasource
        serviceFeaturesTables.delegate = self
        serviceFeaturesTables.dataSource = self
        serviceFeaturesTables.separatorStyle = UITableViewCell.SeparatorStyle.none
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return serviceOverviewScreenModel.supportedFeatures.count
     }
     
     func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
         if let cell = tableView.dequeueReusableCell(withIdentifier: "serviceOverviewTableCell", for: indexPath) as? ServiceOverviewTableCell {
             let supportedFeature = serviceOverviewScreenModel.supportedFeatures[indexPath.row]
             
             //call the update view function from ContactCell
             cell.UpdateCellView(supportedFeature: supportedFeature)
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
