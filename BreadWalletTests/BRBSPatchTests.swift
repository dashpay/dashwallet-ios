//
//  BRBSPatchTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/1/15.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import XCTest
@testable import breadwallet

class BRBSPatchTests: XCTestCase {
    var bundle1Url: NSURL?
    var bundle2Url: NSURL?
    var patchUrl: NSURL?

    override func setUp() {
        // download test files
        func download(urlStr: String, inout resultingUrl: NSURL?) {
            let fm = NSFileManager.defaultManager()
            let url = NSURL(string: urlStr)!
            let documentsUrl =  fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
            let destinationUrl = documentsUrl.URLByAppendingPathComponent(url.lastPathComponent!)!
            if fm.fileExistsAtPath(destinationUrl.path!) {
                print("file already exists [\(destinationUrl.path!)]")
                resultingUrl = destinationUrl
            } else if let dataFromURL = NSData(contentsOfURL: url){
                if dataFromURL.writeToURL(destinationUrl, atomically: true) {
                    print("file saved [\(destinationUrl.path!)]")
                    resultingUrl = destinationUrl
                } else {
                    XCTFail("error saving file")
                }
            } else {
                XCTFail("error downloading file")
            }
        }
        download("https://s3.amazonaws.com/breadwallet-assets/bread-buy/bundle.tar", resultingUrl: &bundle1Url)
        download("https://s3.amazonaws.com/breadwallet-assets/bread-buy/bundle2.tar", resultingUrl: &bundle2Url)
        download("https://s3.amazonaws.com/breadwallet-assets/bread-buy/bundle_bundle2.bspatch", resultingUrl: &patchUrl)
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testPatch() {
        guard let bundle1Url = bundle1Url, bundle2Url = bundle2Url, patchUrl = patchUrl
            else { XCTFail("test files not downloaded successfully"); return }
        let fm = NSFileManager.defaultManager()
        let docsPath = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let destPath = docsPath.URLByAppendingPathComponent("bundle3.tar")!
        if fm.fileExistsAtPath(destPath.path!) {
            do {
                try fm.removeItemAtPath(destPath.path!)
            } catch { XCTFail("unable to remove old test file") }
        }
        var x: UnsafeMutablePointer<CUnsignedChar> = nil
        do {
            x = try BRBSPatch.patch(bundle1Url.path!, newFilePath: destPath.path!, patchFilePath: patchUrl.path!)
        } catch let e {
            XCTFail("failed to patch file: \(e)")
        }
        let b2contents = NSData(contentsOfURL: bundle2Url)!
        let b2contentsRaw = UnsafeMutablePointer<CUnsignedChar>(b2contents.bytes)
        print("should be bytes len \(b2contents.length)")
        let iseq = b2contentsRaw == x
        print("is eq \(iseq)")
        let b3contents = NSData(contentsOfURL: destPath)!
        if !b2contents.isEqualToData(b3contents) {
            XCTFail("patch did not create an identical file")
        }
    }
}
