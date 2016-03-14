//
//  BRGeoLocationPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation
import CoreLocation


@available(iOS 9.0, *)
class BRGeoLocationDelegate: NSObject, CLLocationManagerDelegate {
    var manager: CLLocationManager? = nil
    var response: BRHTTPResponse
    var remove: (() -> Void)? = nil
    
    init(response: BRHTTPResponse) {
        self.response = response
        super.init()
        // location managers MUST operate on the main queue, but requests are not handled there
        
        dispatch_async(self.response.request.queue) {
            let j: [String: AnyObject] = [
                "timestamp": 1,
                "coordinate": ["latitude": 37.7797570, "longitude": -122.4401800],
                "altitude": 0.0,
                "horizontal_accuracy": 0.0,
                "description": "test"
            ]
            self.response.provide(200, json: j)
        }
        
//        dispatch_sync(dispatch_get_main_queue()) { () -> Void in
//            self.manager = CLLocationManager()
//            self.manager?.delegate = self
//        }
    }
    
    func getOne() {
        dispatch_sync(dispatch_get_main_queue()) { () -> Void in
            self.manager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            self.manager?.requestLocation()
        }
    }
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var j = [String: AnyObject]()
        let l = locations.last!
        j["timestamp"] = l.timestamp.description
        j["coordinate"] = ["latitude": l.coordinate.latitude, "longitude": l.coordinate.longitude]
        j["altitude"] = l.altitude
        j["horizontal_accuracy"] = l.horizontalAccuracy
        j["description"] = l.description
        dispatch_async(response.request.queue) {
            self.response.provide(200, json: j)
            self.remove?()
        }
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        var j = [String: AnyObject]()
        j["error"] = error.localizedDescription
        dispatch_async(response.request.queue) {
            self.response.provide(500, json: j)
            self.remove?()
        }
    }
}

@available(iOS 9.0, *)
@objc public class BRGeoLocationPlugin: NSObject, BRHTTPRouterPlugin, CLLocationManagerDelegate {
    lazy var manager = CLLocationManager()
    var outstanding = [BRGeoLocationDelegate]()
    
    override init() {
        super.init()
        self.manager.delegate = self
    }
    
    public func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        print("new authorization status: \(status)")
    }
    
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
        //
        // "user_queried" indicates whether or not the user has already been asked for geolocation
        // "location_enabled" indicates whether or not the user has geo location enabled on their phone
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
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: "geo_permission_was_queried")
                return BRHTTPResponse(request: request, code: 204)
            }
            return BRHTTPResponse(request: request, code: 400)
        }
        
        // GET /_geo
        //
        // Calling this method will query CoreLocation for a location object. The returned value may not be returned
        // very quick (sometimes getting a geo lock takes some time) so be sure to display to the user some status
        // while waiting for a response.
        //
        // Response Object:
        //
        // "coordinates" = { "latitude": double, "longitude": double }
        // "altitude" = double
        // "description" = "a string representation of this object"
        // "timestamp" = "ISO-8601 timestamp of when this location was generated"
        // "horizontal_accuracy" = double
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
            del.remove = {
                objc_sync_enter(self)
                self.outstanding.removeAtIndex(self.outstanding.indexOf({ (d) -> Bool in return d == del })!)
                objc_sync_exit(self)
            }
            objc_sync_enter(self)
            self.outstanding.append(del)
            objc_sync_exit(self)
            
            print("outstanding delegates: \(self.outstanding)")
            
            // get location only once
            del.getOne()
            
            return resp
        }
    }
}
