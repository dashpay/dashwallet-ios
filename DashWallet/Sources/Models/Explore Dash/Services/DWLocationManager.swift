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

import CoreLocation
import Foundation
import Combine

// MARK: - DWLocationObserver

@objc
protocol DWLocationObserver: AnyObject {
    @objc
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation)
    @objc
    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager)
    @objc
    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager)
}

// MARK: - DWLocationManager

@objc
class DWLocationManager: NSObject {
    @objc static let shared = DWLocationManager()
    
    private var locationManager: CLLocationManager
    private var geocoder: CLGeocoder
    private var observers: [DWLocationObserver] = []

    @objc var currentLocation: CLLocation? {
        didSet {
            if let location = currentLocation {
                reverseCurrentLocation()
                observers.forEach { $0.locationManagerDidChangeCurrentLocation(self, location: location) }
            }
        }
    }

    @objc var currentReversedLocation: String? {
        didSet {
            observers.forEach { $0.locationManagerDidChangeCurrentReversedLocation(self) }
        }
    }

    @objc var locationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    @objc var authorizationStatus: CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }

    @objc var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    @objc var needsAuthorization: Bool {
        authorizationStatus == .notDetermined
    }

    @objc var isPermissionDenied: Bool {
        authorizationStatus == .denied
    }
    
    @Published private(set) var currentPlacemark: CLPlacemark? = nil

    override init() {
        locationManager = CLLocationManager()
        locationManager.distanceFilter = 100
        geocoder = CLGeocoder()

        currentLocation = locationManager.location

        super.init()

        locationManager.delegate = self
    }

    @objc
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    @objc
    func add(observer: DWLocationObserver) {
        guard observers.filter({ $0 === observer }).isEmpty else { return }

        observers.append(observer)
    }

    @objc
    func remove(observer: DWLocationObserver) {
        observers = observers.filter { $0 !== observer }
    }

    private func reverseCurrentLocation() {
        guard let loc = currentLocation else { return }
        reverseGeocodeLocation(loc) { [weak self] loc, placemark in
            self?.currentReversedLocation = loc
            self?.currentPlacemark = placemark
        }
    }

    public func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ((String, CLPlacemark?) -> Void)) {
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale.current) { placemarks, error in
            if let placemark = placemarks?.last {
                let loc = [placemark.country, placemark.administrativeArea, placemark.locality].compactMap { $0 }
                    .joined(separator: ", ")
                completion(loc, placemark)
            } else if error != nil {
                completion("Location couldn't determined", nil)
            }
        }
    }
}

// MARK: CLLocationManagerDelegate

extension DWLocationManager: CLLocationManagerDelegate {
    private func startMonitoring(_ manager: CLLocationManager) {
        manager.startUpdatingLocation()
    }

    private func stopMonitoring(_ manager: CLLocationManager) {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            startMonitoring(manager)
        } else {
            stopMonitoring(manager)
        }

        observers.forEach { $0.locationManagerDidChangeServiceAvailability(self) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .denied {
            manager.stopUpdatingLocation()
            observers.forEach { $0.locationManagerDidChangeServiceAvailability(self) }
            return
        }
    }
}

extension DWLocationManager {
    var localizedStatus: String {
        switch authorizationStatus {
        case .notDetermined:
            return NSLocalizedString("Not Determined", comment: "Location Service Status")
        case .restricted:
            return NSLocalizedString("Restricted", comment: "Location Service Status")
        case .denied:
            return NSLocalizedString("Denied", comment: "Location Service Status")
        default:
            return NSLocalizedString("Authorized", comment: "Location Service Status")
        }
    }
}
