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
import SwiftDashSDK

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
            // Recurse like the container branches above: stopping one level
            // into the presentation stack made every "present from the top"
            // caller present from a controller that was itself already
            // presenting (e.g. PIN prompt over the receive sheet's confirm
            // sheet), which UIKit silently drops.
            return vc.topController()
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
        // Zip the recent SwiftDashSDK log sessions off the main actor
        // first (blocking file I/O), then compose. App logs stay as
        // loose attachments — the support workflow already expects
        // them — while the SDK sessions ride along as one zip. A
        // failed/empty SDK export (e.g. first launch after the update
        // that enabled file logging) just omits the zip.
        let network = SwiftDashSDKHost.shared.runningNetwork.map { String(describing: $0) } ?? "unknown"
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let appVersion = "\(short) (\(build))"
        let currentSession = LoggingPreferences.currentSessionDirectory

        Task { [weak self] in
            let sdkLogsZip = await Task.detached(priority: .userInitiated) { () -> URL? in
                try? DiagnosticLogExporter.export(
                    network: network,
                    appVersion: appVersion,
                    currentSession: currentSession,
                    appLogFiles: [])
            }.value
            self?.presentSupportEmailController(sdkLogsZip: sdkLogsZip)
        }
    }

    private func presentSupportEmailController(sdkLogsZip: URL?) {
        let logFiles = DWLogger.sharedInstance().logFiles()

        if MFMailComposeViewController.canSendMail() {
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self as? MFMailComposeViewControllerDelegate

            let email = Bundle.main.infoDictionary?["SupportEmail"] as? String ?? ""
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            mailComposer.setToRecipients([email])
            mailComposer.setSubject(String(format: NSLocalizedString("iOS Dash Wallet: %@ Reported issue", comment: ""), version))

            var totalSize: Int64 = 0
            let maxSize: Int64 = 25 * 1024 * 1024 // 25MB in bytes

            // SDK sessions first — one compressed zip; the app-log
            // loop below fills the remaining attachment budget.
            if let sdkLogsZip, let zipData = try? Data(contentsOf: sdkLogsZip) {
                mailComposer.addAttachmentData(
                    zipData,
                    mimeType: "application/zip",
                    fileName: sdkLogsZip.lastPathComponent)
                totalSize += Int64(zipData.count)
            }

            // Sort log files by modification date, most recent first
            let sortedLogFiles = logFiles.sorted { (url1, url2) -> Bool in
                let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (date1 ?? .distantPast) > (date2 ?? .distantPast)
            }

            for logFileURL in sortedLogFiles {
                guard let logData = try? Data(contentsOf: logFileURL) else {
                    continue
                }

                // Break if this file would exceed the size limit
                if totalSize + Int64(logData.count) > maxSize {
                    break
                }

                let fileName = logFileURL.lastPathComponent
                let mimeType = fileName.hasSuffix(".gz") ? "application/gzip" : "text/plain"
                mailComposer.addAttachmentData(logData, mimeType: mimeType, fileName: fileName)

                totalSize += Int64(logData.count)
            }

            present(mailComposer, animated: true)
        }
        else {
            var activityItems: [Any] = logFiles
            if let sdkLogsZip {
                activityItems.append(sdkLogsZip)
            }
            dw_presentActivityViewController(activityItems: activityItems)
        }
    }
}

extension UIViewController {
    /// Presents a share sheet, supplying the anchor that iPad requires:
    /// there `UIActivityViewController` is always presented as a popover, and
    /// a popover with neither `sourceView` nor `barButtonItem` throws
    /// `NSInvalidArgumentException` from `presentationTransitionWillBegin` —
    /// a hard crash. iPhone never hits it because the sheet is modal there.
    ///
    /// Callers with a tapped control pass it as `sourceView` (plus its
    /// `bounds` as `sourceRect`). Callers driven from SwiftUI have no UIKit
    /// sender, so the default anchors an arrow-less popover at the centre of
    /// this controller's view.
    func dw_presentActivityViewController(
        activityItems: [Any],
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        completion: (() -> Void)? = nil
    ) {
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        if let popover = activityViewController.popoverPresentationController {
            let anchor = sourceView ?? view!
            popover.sourceView = anchor

            if let sourceRect {
                popover.sourceRect = sourceRect
            } else {
                popover.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }

        present(activityViewController, animated: true, completion: completion)
    }
}
