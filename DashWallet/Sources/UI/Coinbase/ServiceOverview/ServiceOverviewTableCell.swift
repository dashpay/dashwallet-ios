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
        featureTitle.numberOfLines = 2
        featureTitle.translatesAutoresizingMaskIntoConstraints = false
        featureTitle.lineBreakMode = .byWordWrapping
        featureTitle.textColor = .label
        featureTitle.font = UIFont.boldSystemFont(ofSize: 16)
    
        
        featureSubtitle.numberOfLines = 2
        featureSubtitle.translatesAutoresizingMaskIntoConstraints = false
        featureSubtitle.lineBreakMode = .byWordWrapping
        featureSubtitle.font = UIFont.systemFont(ofSize: 11)
        featureSubtitle.textColor = .secondaryLabel
        guard let subtitle = supportedFeature.serviceSubtitle else {
            featureSubtitle.isHidden = true
            return
        }
        featureSubtitle.text = subtitle
        
    }
    
}
