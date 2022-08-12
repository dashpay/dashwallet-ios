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
import MapKit

protocol ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleRect rect: CGRect)
    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: Merchant)
}

class ExploreMapView: UIView {
    
    var delegate: ExploreMapViewDelegate?
    
    var userLocation: CLLocation? {
        return mapView.userLocation.location
    }
    
    var initialCenterLocation: CLLocation?
    
    var contentInset: UIEdgeInsets = .zero {
        didSet {
            mapView.layoutMargins = contentInset
        }
    }
    
    private var mapView: MKMapView!
    
    private lazy var showCurrentLocationOnce: Void = {
        if let loc = initialCenterLocation {
            self.setCenter(loc, animated: false)
        }else if let loc = mapView.userLocation.location {
            self.setCenter(loc, animated: false)
        }
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show(merchants: [Merchant]) {
        mapView.addAnnotations(merchants.map({ MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!))}))
    }
    
    public func setCenter(_ location: CLLocation, animated: Bool) {
        let miles: Double = 20.0
        let scalingFactor: Double = abs((cos(2*Double.pi * location.coordinate.latitude/360.0)))
        
        let span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))
        
        let region: MKCoordinateRegion = .init(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: animated)
    }
    
    public func setContentInsets(_ inset: UIEdgeInsets, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                self.contentInset = inset
            } completion: { complete in
                
            }
        }else{
            self.contentInset = inset
        }
    }
    
    @objc func myLocationButtonAction() {
        if let loc = mapView.userLocation.location {
            self.setCenter(loc, animated: true)
        }
    }
    

    
    private func configureHierarchy() {
        self.mapView = MKMapView(frame: bounds)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = self
        mapView.register(MerchantAnnotationView.self, forAnnotationViewWithReuseIdentifier: MerchantAnnotationView.reuseIdentifier)
        addSubview(mapView)
        
        let myLocationButton: UIButton = UIButton(type: .custom)
        myLocationButton.translatesAutoresizingMaskIntoConstraints = false
        myLocationButton.backgroundColor = .dw_background()
        myLocationButton.layer.cornerRadius = 8.0
        myLocationButton.layer.masksToBounds = true
        myLocationButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.12, x: 0, y: 3, blur: 8)
        myLocationButton.setImage(UIImage(named: "image.explore.dash.wts.map.my-location"), for: .normal)
        myLocationButton.addTarget(self, action: #selector(myLocationButtonAction), for: .touchUpInside)
        addSubview(myLocationButton)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: self.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            
            myLocationButton.widthAnchor.constraint(equalToConstant: 40),
            myLocationButton.heightAnchor.constraint(equalToConstant: 40),
            myLocationButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            myLocationButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
        ])
    }
}

extension ExploreMapView: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is MerchantAnnotation:
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MerchantAnnotationView.reuseIdentifier, for: annotation) as! MerchantAnnotationView
            view.update(with: (annotation as! MerchantAnnotation).merchant)
            return view
        default:
            return nil
        }
    }
    
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_mapViewDidChangeVisibleRegion), object: nil)
        self.perform(#selector(_mapViewDidChangeVisibleRegion), with: nil, afterDelay: 1)
    }
    
    @objc func _mapViewDidChangeVisibleRegion() {
        delegate?.exploreMapView(self, didChangeVisibleRect: mapView.region.cgRect)
    }
    
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        _ = showCurrentLocationOnce
        
    }
        
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        mapView.deselectAnnotation(view.annotation, animated: false)
        
        if let annotation = view.annotation as? MerchantAnnotation {
            delegate?.exploreMapView(self, didSelectMerchant: annotation.merchant)
        }
    }
}

extension MKMapRect {
    var cgRect: CGRect {
        return CGRect(origin: .init(x: origin.x, y: origin.y), size: .init(width: size.width, height: size.width))
    }
}

extension MKCoordinateRegion {
    var cgRect: CGRect {
        return CGRect(origin: .init(x: center.longitude - span.longitudeDelta, y: center.latitude - span.latitudeDelta), size: .init(width: span.longitudeDelta*2, height: span.latitudeDelta*2))
    }
}

class MerchantAnnotation: MKPointAnnotation {
    var merchant: Merchant
    
    init(merchant: Merchant, location: CLLocationCoordinate2D) {
        self.merchant = merchant
        super.init()
        self.coordinate = location

    }
}

final class MerchantAnnotationView: MKAnnotationView {
    
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
    
    public func update(with merchant: Merchant) {
        if let str = merchant.logoLocation, let url = URL(string: str)
        {
            imageView.sd_setImage(with: url, completed: nil)
        }else{
            imageView.image = UIImage(named: "image.explore.dash.wts.item.logo.empty")
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
        addSubview(imageView)
        
        imageView.frame = bounds
    }
    
    static var reuseIdentifier: String { return "MerchantAnnotationView" }
}
