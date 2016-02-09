//
//  BRGeoLocationPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation
import CoreLocation


class BRGeoLocationDelegate: NSObject, CLLocationManagerDelegate {
    lazy var manager = CLLocationManager()
    var response: BRHTTPResponse
    var remove: (() -> Void)? = nil
    
    init(response: BRHTTPResponse) {
        self.response = response
        super.init()
        self.manager.delegate = self
    }
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var j = [String: AnyObject]()
        let l = locations.last!
        j["timestamp"] = l.timestamp.description
        j["coordinate"] = ["latitude": l.coordinate.latitude, "longitude": l.coordinate.longitude]
        j["altitude"] = l.altitude
        j["horizontal_accuracy"] = l.horizontalAccuracy
        j["description"] = l.description
        self.response.provide(200, json: j)
        self.remove?()
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        var j = [String: AnyObject]()
        j["error"] = error.localizedDescription
        self.response.provide(500, json: j)
        self.remove?()
    }
}

@available(iOS 9.0, *)
@objc public class BRGeoLocationPlugin: NSObject, BRHTTPRouterPlugin, CLLocationManagerDelegate {
    lazy var manager = CLLocationManager()
    var outstanding = [BRGeoLocationDelegate]()
    
    public func hook(router: BRHTTPRouter) {
        // GET /_permissions/geo
        //
        // Call this method to retrieve the current permission status for geolocation.
        // The returned JSON dictionary contains the following keys:
        //
        // "status" = "denied" | "restricted | "undetermined" | "inuse" | "always"
        // "user_queried" = true | false
        // "location_enabled" = true | false
        //
        // The status correspond to those found in the apple CLLocation documentation: http://apple.co/1O0lHFv
        router.get("/_permissions/geo") { (request, match) -> BRHTTPResponse in
            let userDefaults = NSUserDefaults.standardUserDefaults()
            let authzStatus = CLLocationManager.authorizationStatus()
            var retJson = [String: AnyObject]()
            switch authzStatus {
            case .Denied:
                retJson["status"] = "denied"
            case .Restricted:
                retJson["status"] = "restricted"
            case .NotDetermined:
                retJson["status"] = "undetermined"
            case .AuthorizedWhenInUse:
                retJson["status"] = "inuse"
            case .AuthorizedAlways:
                retJson["status"] = "always"
            }
            retJson["user_queried"] = userDefaults.boolForKey("geo_permission_was_queried")
            retJson["location_enabled"] = CLLocationManager.locationServicesEnabled()
            return try BRHTTPResponse(request: request, code: 200, json: retJson)
        }
        
        // POST /_permissions/geo
        //
        // Call this method to request the geo permission from the user.
        // The request body should be a JSON dictionary containing a single key, "style"
        // the value of which should be either "inuse" or "always" - these correspond to the
        // two ways the user can authorize geo access to the app. "inuse" will request
        // geo availability to the app when the app is foregrounded, and "always" will request
        // full time geo availability to the app
        router.post("/_permissions/geo") { (request, match) -> BRHTTPResponse in
            if let j = request.json?(), dict = j as? NSDictionary, style = dict["style"] as? String {
                switch style {
                case "inuse": self.manager.requestWhenInUseAuthorization()
                case "always": self.manager.requestAlwaysAuthorization()
                default: return BRHTTPResponse(request: request, code: 400)
                }
                return BRHTTPResponse(request: request, code: 204)
            }
            return BRHTTPResponse(request: request, code: 400)
        }
        
        // GET /_geo
        router.get("/_geo") { (request, match) -> BRHTTPResponse in
            var retJson = [String: AnyObject]()
            if !CLLocationManager.locationServicesEnabled() {
                retJson["error"] = NSLocalizedString("Location services are disabled", comment: "")
                return try BRHTTPResponse(request: request, code: 400, json: retJson)
            }
            let authzStatus = CLLocationManager.authorizationStatus()
            if authzStatus != .AuthorizedWhenInUse && authzStatus != .AuthorizedAlways {
                retJson["error"] = NSLocalizedString("Location services are not authorized", comment: "")
                return try BRHTTPResponse(request: request, code: 400, json: retJson)
            }
            let resp = BRHTTPResponse(async: request)
            let del = BRGeoLocationDelegate(response: resp)
            del.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            del.manager.requestLocation()
            del.remove = {
                objc_sync_enter(self)
                self.outstanding.removeAtIndex(self.outstanding.indexOf({ (d) -> Bool in return d == del })!)
                objc_sync_exit(self)
            }
            objc_sync_enter(self)
            self.outstanding.append(del)
            objc_sync_exit(self)
            return resp
        }
    }
}
