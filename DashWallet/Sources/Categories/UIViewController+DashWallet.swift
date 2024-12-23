//
//  Created by tkhp
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
import MessageUI

@objc
extension UIViewController {
    @objc
    func topController() -> UIViewController {
        if let vc = self as? UITabBarController {
            if let vc = vc.selectedViewController {
                return vc.topController()
            }

            return vc
        } else if let vc = self as? UINavigationController {
            if let vc = vc.visibleViewController {
                return vc.topController()
            }

            return vc
        } else if let vc = presentedViewController {
            return vc
        }

        return self
    }

    @objc
    class func deviceSpecificBottomPadding() -> CGFloat {
        if UIDevice.isIpad { // All iPads including ones with home indicator
            return 24.0;
        } else if UIDevice.hasHomeIndicator { // iPhone X-like, XS Max, X
            return 4.0;
        } else if UIDevice.isIphone6Plus { // iPhone 6 Plus-like
            return 20.0;
        } else { // iPhone 5-like, 6-like
            return 16.0;
        }
    }

    @objc func presentSupportEmailController() {
        let logFiles = DSLogger.sharedInstance().logFiles()
        
        if MFMailComposeViewController.canSendMail() {
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self as? MFMailComposeViewControllerDelegate
            
            let email = Bundle.main.infoDictionary?["SupportEmail"] as? String ?? ""
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            mailComposer.setToRecipients([email])
            mailComposer.setSubject(String(format: NSLocalizedString("iOS Dash Wallet: %@ Reported issue", comment: ""), version))
            
            // Sort log files by modification date, most recent first
            let sortedLogFiles = logFiles.sorted { (url1, url2) -> Bool in
                let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (date1 ?? .distantPast) > (date2 ?? .distantPast)
            }
            
            var totalSize: Int64 = 0
            let maxSize: Int64 = 25 * 1024 * 1024 // 25MB in bytes
            
            for logFileURL in sortedLogFiles {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
                      let fileSize = attributes[.size] as? Int64 else { continue }
                
                // Break if this file would exceed the size limit
                if totalSize + fileSize > maxSize { break }
                
                guard let logData = try? Data(contentsOf: logFileURL) else { continue }
                let fileName = logFileURL.lastPathComponent
                let mimeType = fileName.hasSuffix(".gz") ? "application/gzip" : "text/plain"
                mailComposer.addAttachmentData(logData, mimeType: mimeType, fileName: fileName)
                
                totalSize += fileSize
            }
            
            present(mailComposer, animated: true)
        }
        else {
            let activityViewController = UIActivityViewController(
                activityItems: logFiles,
                applicationActivities: nil
            )
            present(activityViewController, animated: true)
        }
    }
}
