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

import MapKit

// MARK: - MerchantAnnotation

class MerchantAnnotation: MKPointAnnotation {
    var merchant: ExplorePointOfUse

    init(merchant: ExplorePointOfUse, location: CLLocationCoordinate2D) {
        self.merchant = merchant
        super.init()
        coordinate = location
    }

    // Override hash to use merchant ID for consistent hashing
    override var hash: Int {
        merchant.id.hashValue
    }

    // Override isEqual for Set comparison
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MerchantAnnotation else {
            return false
        }
        return merchant.id == other.merchant.id
    }
}

// MARK: - ExploreMapAnnotationView

final class ExploreMapAnnotationView: MKAnnotationView {

    private var imageView: UIImageView!

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        centerOffset = CGPoint(x: 0, y: -frame.size.height / 2)

        canShowCallout = true
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(with pointOfUse: ExplorePointOfUse) {
        if let str = pointOfUse.logoLocation, let url = URL(string: str) {
            imageView.sd_setImage(with: url, completed: nil)
        } else {
            imageView.image = UIImage(named: pointOfUse.emptyLogoImageName)
        }
    }

    private func configureHierarchy() {
        backgroundColor = .clear

        imageView = UIImageView()
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 18
        imageView.layer.masksToBounds = true
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.layer.borderWidth = 2
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        imageView.frame = bounds
    }
}


