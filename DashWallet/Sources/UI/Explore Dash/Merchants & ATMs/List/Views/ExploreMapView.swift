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
        mapBounds(with: searchRadius)
    }

    // Search radius in meters - defaults to 32km
    var searchRadius: Double = kDefaultRadius

    func mapBounds(with radius: Double) -> ExploreMapBounds {
        .init(rect: MKCircle(center: centerCoordinate, radius: radius).boundingMapRect)
    }

    private var shownMerchantsAnnotations: [MerchantAnnotation] = []

    private var hasSetInitialCenter = false
    private var isSettingInitialRegion = false
    private var desiredCenter: CLLocationCoordinate2D?
    private var pendingMerchantsToShow: [ExplorePointOfUse]?
    private var regionStabilizationTimer: Timer?

    private lazy var showCurrentLocationOnce: Void = {
        print("🔍 MAP: showCurrentLocationOnce called")
        print("🔍 MAP: hasSetInitialCenter = \(hasSetInitialCenter)")
        print("🔍 MAP: initialCenterLocation = \(initialCenterLocation?.coordinate.latitude ?? 0), \(initialCenterLocation?.coordinate.longitude ?? 0)")
        print("🔍 MAP: mapView.userLocation.location = \(mapView.userLocation.location?.coordinate.latitude ?? 0), \(mapView.userLocation.location?.coordinate.longitude ?? 0)")

        // Only auto-center if we haven't already set a center
        guard !hasSetInitialCenter else {
            print("🔍 MAP: Skipping auto-center - already set")
            return
        }

        if let loc = initialCenterLocation {
            print("🔍 MAP: Using initialCenterLocation")
            self.setCenter(loc, animated: false)
            hasSetInitialCenter = true
        } else if let loc = mapView.userLocation.location {
            print("🔍 MAP: Using mapView.userLocation.location")
            self.setCenter(loc, animated: false)
            hasSetInitialCenter = true
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
        print("🔍 ANNOTATIONS: show() called with \(merchants.count) merchants")

        // If we're still setting the initial region, defer adding annotations
        if isSettingInitialRegion {
            print("🔍 ANNOTATIONS: Deferring annotation updates until initial region is set")
            pendingMerchantsToShow = merchants
            return
        }

        _showAnnotations(merchants: merchants)
    }

    private func _showAnnotations(merchants: [ExplorePointOfUse]) {
        print("🔍 ANNOTATIONS: _showAnnotations called with \(merchants.count) merchants")

        // Filter to only merchants with valid coordinates
        let merchantsWithCoords = merchants.filter { $0.latitude != nil && $0.longitude != nil }
        print("🔍 ANNOTATIONS: \(merchantsWithCoords.count) have coordinates")

        if shownMerchantsAnnotations.isEmpty {
            let newAnnotations = merchantsWithCoords
                .map { MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!)) }
            print("🔍 ANNOTATIONS: Initial load - adding \(newAnnotations.count) annotations")
            shownMerchantsAnnotations = newAnnotations
            mapView.addAnnotations(newAnnotations)
        } else {
            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let wSelf = self else { return }

                let currentAnnotations = Set(wSelf.shownMerchantsAnnotations)
                let newMerchants = Set(merchantsWithCoords
                    .map { MerchantAnnotation(merchant: $0, location: .init(latitude: $0.latitude!, longitude: $0.longitude!)) })

                let toAdd = newMerchants.subtracting(currentAnnotations)
                let toDelete = currentAnnotations.subtracting(newMerchants)
                let toKeep = currentAnnotations.subtracting(toDelete)

                print("🔍 ANNOTATIONS: Update - keeping \(toKeep.count), adding \(toAdd.count), removing \(toDelete.count)")

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
        print("🔍 MAP: setCenter called with \(location.coordinate.latitude), \(location.coordinate.longitude)")
        isSettingInitialRegion = true
        desiredCenter = location.coordinate
        let miles: Double = centerRadius
        let scalingFactor: Double = abs(cos(2*Double.pi * location.coordinate.latitude/360.0))

        let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))

        let region: MKCoordinateRegion = .init(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: animated)
        hasSetInitialCenter = true

        // Allow region change callbacks after a short delay to ensure map settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("🔍 MAP: Initial region setup complete, now adding pending merchants")

            // Add pending merchants while STILL blocking region changes
            if let pending = self.pendingMerchantsToShow {
                print("🔍 MAP: Adding \(pending.count) pending merchants now that region is set")
                self.pendingMerchantsToShow = nil
                // Call internal method to bypass the isSettingInitialRegion check
                self._showAnnotations(merchants: pending)

                // After annotations are added, force the region back and start monitoring for stabilization
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let desired = self.desiredCenter {
                        print("🔍 MAP: Annotations added, forcing region back to \(desired.latitude), \(desired.longitude)")
                        let miles: Double = self.centerRadius
                        let scalingFactor: Double = abs(cos(2*Double.pi * desired.latitude/360.0))
                        let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))
                        let region = MKCoordinateRegion(center: desired, span: span)
                        self.mapView.setRegion(region, animated: false)
                        print("🔍 MAP: Region forced back, current center = \(self.mapView.centerCoordinate.latitude), \(self.mapView.centerCoordinate.longitude)")

                        // Start monitoring for stabilization - lock will be released when region stabilizes
                        self.regionStabilizationTimer?.invalidate()
                        self.regionStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                            self?.checkRegionStabilization()
                        }
                    } else {
                        // No desired center, just release immediately
                        print("🔍 MAP: No desired center to maintain, releasing lock")
                        self.isSettingInitialRegion = false
                    }
                }
            } else {
                // No pending merchants, just release the lock
                print("🔍 MAP: No pending merchants, releasing lock")
                self.isSettingInitialRegion = false
                self.desiredCenter = nil
            }
        }
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
        // Ensure user location annotation has highest priority
        if let userView = views.first(where: { $0.annotation is MKUserLocation }) {
            DispatchQueue.main.async {
                userView.zPriority = .max
            }
        }

        // If we're setting initial region and annotations are being added,
        // force the map back to the desired center
        if let desired = desiredCenter, isSettingInitialRegion {
            let currentDistance = abs(mapView.centerCoordinate.latitude - desired.latitude) +
                                abs(mapView.centerCoordinate.longitude - desired.longitude)
            // If map has drifted more than 0.01 degrees (~1km), recenter it
            if currentDistance > 0.01 {
                print("🔍 MAP: Annotations caused drift, recentering to \(desired.latitude), \(desired.longitude)")
                let miles: Double = centerRadius
                let scalingFactor: Double = abs(cos(2*Double.pi * desired.latitude/360.0))
                let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))
                let region = MKCoordinateRegion(center: desired, span: span)
                mapView.setRegion(region, animated: false)
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
        // Don't respond to region changes during initial setup
        guard !isSettingInitialRegion else {
            print("🔍 MAP: Ignoring region change during initial setup (center=\(mapView.centerCoordinate.latitude), \(mapView.centerCoordinate.longitude))")

            // If we have a desired center and the map has drifted significantly, force it back
            if let desired = desiredCenter {
                let currentDistance = abs(mapView.centerCoordinate.latitude - desired.latitude) +
                                    abs(mapView.centerCoordinate.longitude - desired.longitude)
                if currentDistance > 0.01 {
                    print("🔍 MAP: Map drifted during setup, forcing back to \(desired.latitude), \(desired.longitude)")
                    let miles: Double = centerRadius
                    let scalingFactor: Double = abs(cos(2*Double.pi * desired.latitude/360.0))
                    let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))
                    let region = MKCoordinateRegion(center: desired, span: span)
                    mapView.setRegion(region, animated: false)

                    // Reset stabilization monitoring
                    regionStabilizationTimer?.invalidate()
                    regionStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                        self?.checkRegionStabilization()
                    }
                } else {
                    // Region is close enough to desired, start stabilization check
                    if regionStabilizationTimer == nil {
                        print("🔍 MAP: Region close to desired, starting stabilization check")
                        regionStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                            self?.checkRegionStabilization()
                        }
                    }
                }
            }
            return
        }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_mapViewDidChangeVisibleRegion), object: nil)
        perform(#selector(_mapViewDidChangeVisibleRegion), with: nil, afterDelay: 1)
    }

    private func checkRegionStabilization() {
        guard let desired = desiredCenter else { return }

        let currentDistance = abs(mapView.centerCoordinate.latitude - desired.latitude) +
                            abs(mapView.centerCoordinate.longitude - desired.longitude)

        if currentDistance < 0.001 {
            print("🔍 MAP: Region stabilized at desired center, releasing lock")
            isSettingInitialRegion = false
            desiredCenter = nil
            regionStabilizationTimer = nil
        } else {
            print("🔍 MAP: Region not yet stable (distance=\(currentDistance)), waiting longer")
            // Not stable yet, force it back and wait again
            let miles: Double = centerRadius
            let scalingFactor: Double = abs(cos(2*Double.pi * desired.latitude/360.0))
            let span = MKCoordinateSpan(latitudeDelta: miles/69.0, longitudeDelta: miles/(scalingFactor*69.0))
            let region = MKCoordinateRegion(center: desired, span: span)
            mapView.setRegion(region, animated: false)

            regionStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.checkRegionStabilization()
            }
        }
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



