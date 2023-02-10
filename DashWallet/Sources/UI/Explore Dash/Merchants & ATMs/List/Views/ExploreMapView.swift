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
import UIKit

// MARK: - CLLocationCoordinate2D + Equatable

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.longitude == rhs.longitude && lhs.latitude == rhs.latitude
    }
}

// MARK: - ExploreMapBounds + Equatable

extension ExploreMapBounds: Equatable {
    static func == (lhs: ExploreMapBounds, rhs: ExploreMapBounds) -> Bool {
        lhs.neCoordinate == rhs.neCoordinate && lhs.swCoordinate == rhs.swCoordinate
    }
}

// MARK: - ExploreMapBounds

struct ExploreMapBounds {
    let neCoordinate: CLLocationCoordinate2D
    let swCoordinate: CLLocationCoordinate2D

    var center: CLLocationCoordinate2D {
        let dLon = (neCoordinate.longitude - swCoordinate.longitude).degreesToRadians
        let lat1 = swCoordinate.latitude.degreesToRadians
        let lat2 = neCoordinate.latitude.degreesToRadians
        let lon1 = swCoordinate.longitude.degreesToRadians

        let bX = cos(lat2) + cos(dLon)
        let bY = cos(lat2) * sin(dLon)

        let lat = atan2(sin(lat1) + sin(lat2), sqrt((cos(lat1) + bX) * (cos(lat1) + bX) + bY * bY))
        let lon = lon1 + atan2(bY, cos(lat1) + bX)
        let center = CLLocationCoordinate2D(latitude: lat.radiansToDegrees, longitude: lon.radiansToDegrees)
        return center
    }

    init(rect: MKMapRect) {
        let neMapPoint = MKMapPoint(x: rect.maxX, y: rect.origin.y)
        let swMapPoint = MKMapPoint(x: rect.origin.x, y: rect.maxY)

        neCoordinate = neMapPoint.coordinate
        swCoordinate = swMapPoint.coordinate
    }
}

// MARK: - ExploreMapViewDelegate

protocol ExploreMapViewDelegate {
    func exploreMapView(_ mapView: ExploreMapView, didChangeVisibleBounds bounds: ExploreMapBounds)
    func exploreMapView(_ mapView: ExploreMapView, didSelectMerchant merchant: ExplorePointOfUse)
}

// MARK: - ExploreMapView

class ExploreMapView: UIView {

    var delegate: ExploreMapViewDelegate?

    var userLocation: CLLocation? {
        mapView.userLocation.location
    }

    var centerCoordinate: CLLocationCoordinate2D {
        mapView.centerCoordinate
    }

    var initialCenterLocation: CLLocation?
    var centerRadius: Double = 20
    var contentInset: UIEdgeInsets = .zero {
        didSet {
            mapView.layoutMargins = contentInset
        }
    }

    var userRadius: Double? {
        guard mapView.isUserLocationVisible else { return nil }
        guard let userLocation else { return nil }

        let swLocation = CLLocation(latitude: mapBounds.swCoordinate.latitude, longitude: mapBounds.swCoordinate.longitude)
        let neLocation = CLLocation(latitude: mapBounds.neCoordinate.latitude, longitude: mapBounds.neCoordinate.longitude)

        return max(userLocation.distance(from: swLocation), userLocation.distance(from: neLocation))
    }

    private var mapView: MKMapView!

    var mapBounds: ExploreMapBounds {
        mapBounds(with: 32000)
    }

    func mapBounds(with radius: Double) -> ExploreMapBounds {
        .init(rect: MKCircle(center: centerCoordinate, radius: radius).boundingMapRect)
    }

    private var shownMerchantsAnnotations: [MerchantAnnotation] = []

    private lazy var showCurrentLocationOnce: Void = {
        if let loc = initialCenterLocation {
            self.setCenter(loc, animated: false)
        } else if let loc = mapView.userLocation.location {
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

    public func reloadAnnotations() { }

    public func show(merchants: [ExplorePointOfUse]) {
        if shownMerchantsAnnotations.isEmpty {
            let newAnnotations = merchants
                .map { MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!)) }
            shownMerchantsAnnotations = newAnnotations
            mapView.addAnnotations(newAnnotations)
        } else {
            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let wSelf = self else { return }

                let currentAnnotations = Set(wSelf.shownMerchantsAnnotations)
                let newMerchants = Set(merchants
                    .map { MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!)) })

                let toAdd = newMerchants.subtracting(currentAnnotations)
                let toDelete = currentAnnotations.subtracting(newMerchants)
                let toKeep = currentAnnotations.subtracting(toDelete)

                wSelf.shownMerchantsAnnotations = Array(toKeep.union(toAdd))

                DispatchQueue.main.async {
                    if !toDelete.isEmpty {
                        wSelf.mapView.removeAnnotations(Array(toDelete))
                    }

                    if !toAdd.isEmpty {
                        wSelf.mapView.addAnnotations(Array(toAdd))
                    }
                }
            }
        }
    }

    public func setCenter(_ location: CLLocation, animated: Bool) {
        let miles: Double = centerRadius
        let scalingFactor: Double = abs(cos(2*Double.pi * location.coordinate.latitude/360.0))

        let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))

        let region: MKCoordinateRegion = .init(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: animated)
    }

    public func showUserLocationInCenter(animated: Bool) {
        if let loc = mapView.userLocation.location {
            setCenter(loc, animated: true)
        }
    }

    public func setContentInsets(_ inset: UIEdgeInsets, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                self.contentInset = inset
            } completion: { _ in
            }
        } else {
            contentInset = inset
        }
    }

    @objc
    func myLocationButtonAction() {
        showUserLocationInCenter(animated: true)
    }

    private func configureHierarchy() {
        mapView = MKMapView(frame: bounds)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = self
        mapView.register(ExploreMapAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: ExploreMapAnnotationView.reuseIdentifier)
        addSubview(mapView)

        let myLocationButton = UIButton(type: .custom)
        myLocationButton.translatesAutoresizingMaskIntoConstraints = false
        myLocationButton.backgroundColor = .dw_secondaryBackground()
        myLocationButton.layer.cornerRadius = 8.0
        myLocationButton.layer.masksToBounds = true
        myLocationButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.12, x: 0, y: 3, blur: 8)
        myLocationButton.setImage(UIImage(named: "image.explore.dash.wts.map.my-location"), for: .normal)
        myLocationButton.addTarget(self, action: #selector(myLocationButtonAction), for: .touchUpInside)
        addSubview(myLocationButton)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),

            myLocationButton.widthAnchor.constraint(equalToConstant: 40),
            myLocationButton.heightAnchor.constraint(equalToConstant: 40),
            myLocationButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            myLocationButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }
}

// MARK: MKMapViewDelegate

extension ExploreMapView: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        guard let view = views.first(where: { $0.annotation is MKUserLocation }) else { return }
        DispatchQueue.main.async {
            if #available(iOS 14.0, *) {
                view.zPriority = .max
            } else {
                view.layer.zPosition = CGFloat.greatestFiniteMagnitude
            }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is MerchantAnnotation:
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: ExploreMapAnnotationView.reuseIdentifier,
                                                             for: annotation) as! ExploreMapAnnotationView
            view.update(with: (annotation as! MerchantAnnotation).merchant)
            return view
        default:
            return nil
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_mapViewDidChangeVisibleRegion), object: nil)
        perform(#selector(_mapViewDidChangeVisibleRegion), with: nil, afterDelay: 1)
    }

    @objc
    func _mapViewDidChangeVisibleRegion() {
        delegate?.exploreMapView(self, didChangeVisibleBounds: mapBounds)
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



