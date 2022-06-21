//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit

class TxReclassifyTransactionsWhereToChangeViewController: BasePageSheetViewController {
    var transactionScreenImage: UIImage!
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var container: UIView!
    @IBOutlet var imageView: UIImageView!
    
    func imageWithSize(image: UIImage, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
    
    func resizeImageWithAspect(image: UIImage, width: CGFloat) -> UIImage
    {
        let oldWidth = image.size.width;
        let oldHeight = image.size.height;
        
        let scaleFactor = width/oldWidth
        
        let newHeight = oldHeight * scaleFactor;
        let newWidth = oldWidth * scaleFactor;
        let newSize = CGSize(width: newWidth, height: newHeight);
        
        return imageWithSize(image: image, size: newSize);
    }
    
    private func configureHierarchy() {
        titleLabel.font = UIFont.dw_font(forTextStyle: .title2).withWeight(UIFont.Weight.bold.rawValue)
        subtitleLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
        subtitleLabel.textColor = .darkGray
        
        let containerLayer = CAGradientLayer()
        containerLayer.colors = [
            UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1).cgColor,
            UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1).cgColor
        ]
        containerLayer.locations = [0, 1]
        containerLayer.startPoint = CGPoint(x: 0.25, y: 0.5)
        containerLayer.endPoint = CGPoint(x: 0.75, y: 0.5)
        containerLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0))
        containerLayer.bounds = container.bounds.insetBy(dx: -0.5*container.bounds.size.width, dy: -0.5*container.bounds.size.height)
        containerLayer.position = container.center
        container.layer.insertSublayer(containerLayer, at: 0)
        
        let img = resizeImageWithAspect(image: transactionScreenImage, width: view.bounds.width - 120)
        imageView.contentMode = .top
        imageView.image = img
        imageView.layer.masksToBounds = true
        imageView.layer.isOpaque = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
        configureHierarchy()
    }
    
    @objc static func controller() -> TxReclassifyTransactionsWhereToChangeViewController {
        let storyboard = UIStoryboard(name: "Tx", bundle: nil)
        let vc = storyboard.instantiateViewController(identifier: "TxReclassifyTransactionsWhereToChangeViewController") as! TxReclassifyTransactionsWhereToChangeViewController
        return vc
    }
}
