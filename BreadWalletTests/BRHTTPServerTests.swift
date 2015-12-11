//
//  BRHTTPServerTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/10/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import XCTest
@testable import breadwallet

class BRHTTPServerTests: XCTestCase {
    var server: BRHTTPServer!
    var bundle1Url: NSURL?
    var bundle1Data: NSData?

    override func setUp() {
        super.setUp()
        let fm = NSFileManager.defaultManager()
        let documentsUrl =  fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        
        // download test files
        func download(urlStr: String, inout resultingUrl: NSURL?, inout resultingData: NSData?) {
            let url = NSURL(string: urlStr)!
            let destinationUrl = documentsUrl.URLByAppendingPathComponent(url.lastPathComponent!)
            if fm.fileExistsAtPath(destinationUrl.path!) {
                print("file already exists [\(destinationUrl.path!)]")
                resultingData = NSData(contentsOfURL: destinationUrl)
                resultingUrl = destinationUrl
            } else if let dataFromURL = NSData(contentsOfURL: url){
                if dataFromURL.writeToURL(destinationUrl, atomically: true) {
                    print("file saved [\(destinationUrl.path!)]")
                    resultingData = dataFromURL
                    resultingUrl = destinationUrl
                } else {
                    XCTFail("error saving file")
                }
            } else {
                XCTFail("error downloading file")
            }
        }
        download("https://s3.amazonaws.com/breadwallet-assets/bread-buy/bundle.tar",
                 resultingUrl: &bundle1Url, resultingData: &bundle1Data)
        
        server = BRHTTPServer(baseDirectory: documentsUrl)
        do {
            try server.start()
        } catch let e {
            XCTFail("could not start server \(e)")
        }
    }
    
    override func tearDown() {
        super.tearDown()
        server.stop()
        server = nil
    }

    func testDownloadFile() {
        let exp = expectationWithDescription("load")
        
        let url = NSURL(string: "http://localhost:8888/bundle.tar")!
        let req = NSURLRequest(URL: url)
        NSURLSession.sharedSession().dataTaskWithRequest(req) { (data, resp, error) -> Void in
            NSLog("error: \(error)")
            let httpResp = resp as! NSHTTPURLResponse
            NSLog("status: \(httpResp.statusCode)")
            NSLog("headers: \(httpResp.allHeaderFields)")
            
            XCTAssert(data!.isEqualToData(self.bundle1Data!), "data should be equal to that stored on disk")
            exp.fulfill()
        }.resume()
        
        waitForExpectationsWithTimeout(5.0) { (err) -> Void in
            if err != nil {
                NSLog("timeout error \(err)")
            }
        }
    }
}
