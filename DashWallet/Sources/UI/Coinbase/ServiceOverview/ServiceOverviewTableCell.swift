//
//  ServiceFeatureCell.swift
//  Coinbase
//
//  Created by hadia on 04/10/2022.
//

import UIKit

class ServiceOverviewTableCell: UITableViewCell {
    
    @IBOutlet weak var featureIcon: UIImageView!
    @IBOutlet weak var featureTitle: UILabel!
    @IBOutlet weak var featureSubtitle: UILabel!
    
    func updateCellView(supportedFeature: SupportedFeature) {
        featureIcon.image = UIImage(named: supportedFeature.imageName)
       
        featureTitle.text = supportedFeature.serviceName
        guard let subtitle = supportedFeature.serviceSubtitle else {
            featureSubtitle.isHidden = true
            return
        }
        featureSubtitle.text = subtitle
        
    }
    
}
