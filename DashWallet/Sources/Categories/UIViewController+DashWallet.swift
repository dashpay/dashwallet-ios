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

import Intents
import UIKit
import MessageUI

@objc
extension UIViewController {
    /// The tab bar controller somewhere at or under this one, searching
    /// children and then anything presented.
    ///
    /// Downwards, not upwards: a controller shown as a sheet sits outside the
    /// tab bar's hierarchy, so `tabBarController` is nil for it and walking
    /// presenters only finds whoever called `present`. Started from the
    /// window's root this finds the tab bar from anywhere.
    ///
    /// Two private copies of this already exist (`SwapTransactionStatus…`,
    /// `BuyReceive…`); this is the shared one they should collapse into.
    @objc
    func dw_firstTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController { return tabBarController }
        for child in children {
            if let tabBarController = child.dw_firstTabBarController() { return tabBarController }
        }
        if let presented = presentedViewController {
            return presented.dw_firstTabBarController()
        }
        return nil
    }

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
        // No screen-local re-entry flag. `exportArchive` owns the only fact
        // that decides it — a snapshot still in flight — and holds it for the
        // whole pass, past Cancel and past the gate's timeout, which a flag
        // cleared when the export returns cannot match. Every tap therefore
        // reaches the exporter: refused silently while its card is up (the
        // card is the explanation), and refused into the alert once it is
        // gone, which is the only feedback left at that point.
        Task { [weak self] in
            let result = await DiagnosticLogExporter.exportArchive(includingWalletSnapshot: true)
            guard let self else { return }
            switch result {
            case .success(let archive):
                await self.presentSupportEmailController(logsArchive: archive)
            case .failure(let error):
                // Cancel is the user's own choice, and a refusal whose owner
                // is still on screen is already explained by that card — this
                // alert would be drawn under the overlay window either way.
                if DiagnosticLogExporter.shouldStaySilent(about: error) { return }
                self.presentLogsNotAttachedAlert(message: error.localizedDescription)
            }
        }
    }

    /// Never compose silently without the logs the user believes are
    /// attached: say what is missing and let them decide. Reached from an
    /// export failure and from an archive that exists but could not be read.
    ///
    /// "Without logs" means without the archive, not without evidence: the
    /// composer still attaches the app's own CocoaLumberjack files, which is
    /// what the pre-archive build guaranteed. Say so, or the user declines a
    /// report that would in fact have carried something to read.
    private func presentLogsNotAttachedAlert(message: String) {
        var body = message
        if !DWLogger.sharedInstance().logFiles().isEmpty {
            body += "\n\n" + NSLocalizedString(
                "The app's own logs will still be attached.",
                comment: "Support")
        }
        let alert = UIAlertController(
            title: NSLocalizedString("Logs could not be attached", comment: "Support"),
            message: body,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Send Without Logs", comment: "Support"),
            style: .default) { [weak self] _ in
                Task { await self?.presentSupportEmailController(logsArchive: nil) }
            })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    /// Mail rejects attachments over roughly this size at send time — after
    /// the user has written the report — so larger archives go out through
    /// the share sheet, which hands the file over by URL.
    private static let maxMailAttachmentBytes: UInt64 = 25 * 1024 * 1024

    /// Attach the app's own log files individually, newest-first under the
    /// exporter's byte cap. The fallback when there is no archive; reads are
    /// file I/O, so they happen off the main actor.
    private func attachAppLogs(to composer: MFMailComposeViewController) async {
        let files = DiagnosticLogExporter.selectAppLogs(DWLogger.sharedInstance().logFiles())
        guard !files.isEmpty else { return }
        let payloads = await Task.detached(priority: .userInitiated) {
            files.compactMap { url -> (name: String, data: Data)? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (name: url.lastPathComponent, data: data)
            }
        }.value
        for payload in payloads {
            composer.addAttachmentData(
                payload.data,
                mimeType: "text/plain",
                fileName: payload.name)
        }
        DWLogger.log("Support composed without an archive; attached \(payloads.count) app log file(s)")
    }

    private func presentSupportEmailController(logsArchive: URL?) async {
        let email = Bundle.main.infoDictionary?["SupportEmail"] as? String ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let subject = String(format: NSLocalizedString("iOS Dash Wallet: %@ Reported issue", comment: ""), version)
        // `nil` is "size unknown", which must land on the share-sheet side of
        // the cap: an unreadable size on a large-wallet archive is exactly
        // the case where an in-memory read and a mail attachment would fail
        // — silently, and after the user has written the report.
        let archiveBytes: UInt64? = logsArchive.flatMap {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64(max(0, $0)) }
        }
        let fitsInMail = logsArchive == nil
            || (archiveBytes.map { $0 <= Self.maxMailAttachmentBytes } ?? false)

        if MFMailComposeViewController.canSendMail(), fitsInMail {
            // The read is file I/O of up to the cap: off the main actor.
            var zipData: Data?
            if let logsArchive {
                zipData = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: logsArchive)
                }.value
                // The archive exists but could not be read (memory pressure,
                // temp file evicted): that is the log-less send the alert
                // exists to prevent, not a case to fall through.
                guard zipData != nil else {
                    DWLogger.log("Support archive could not be read for attachment; asking before composing without it")
                    presentLogsNotAttachedAlert(message: NSLocalizedString(
                        "The diagnostic archive could not be read.",
                        comment: "Support"))
                    return
                }
            }
            let mailComposer = MFMailComposeViewController()
            mailComposer.mailComposeDelegate = self as? MFMailComposeViewControllerDelegate
            mailComposer.setToRecipients([email])
            mailComposer.setSubject(subject)
            if let logsArchive, let zipData {
                mailComposer.addAttachmentData(
                    zipData,
                    mimeType: "application/zip",
                    fileName: logsArchive.lastPathComponent)
            } else {
                // No archive: attach the app's own logs directly, which is
                // what this screen did before the archive existed. Everything
                // riding on one zip meant a single throw in `export()` — a
                // rolled session directory, a full disk, `noLogsFound` on the
                // first launch after an update — sent support a ticket with
                // nothing in it, on the device where something had gone wrong.
                await attachAppLogs(to: mailComposer)
            }
            present(mailComposer, animated: true)
        }
        else {
            if let logsArchive, !fitsInMail {
                DWLogger.log("Support archive \(archiveBytes.map { "is \($0) bytes, over" } ?? "has an unreadable size, treated as over") the mail attachment limit; sharing \(logsArchive.lastPathComponent) by URL instead")
            }
            // No Apple Mail account configured (common when the customer lives in Gmail), so
            // `MFMailComposeViewController` is unavailable — or the archive is too large for
            // it — and the logs go out through the share sheet instead. Lead with a mail item
            // carrying the support address and subject: handlers that understand `mailto:`
            // prefill the recipient from it, and the rest at least show the address in the
            // composed body — the previous items were log files only, which is why reports
            // arrived with an empty "To" field.
            var activityItems: [Any] = []
            if !email.isEmpty {
                activityItems.append(SupportRecipientActivityItem(email: email, subject: subject))
            }
            if let logsArchive {
                activityItems.append(logsArchive)
            } else {
                // Same fallback as the mail path: the share sheet takes the
                // app log files by URL, so no read is needed here.
                activityItems.append(contentsOf: DiagnosticLogExporter.selectAppLogs(
                    DWLogger.sharedInstance().logFiles()))
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
        completion: (() -> Void)? = nil,
        dismissal: (() -> Void)? = nil
    ) {
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            dismissal?()
        }

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

/// Carries the support destination into the share sheet used when `MFMailComposeViewController`
/// is unavailable. Recipients travel three ways, because no single one reaches every handler:
/// `activityViewControllerShareRecipients(_:)` for extensions that read recipient metadata, a
/// `mailto:` URL for mail activities that parse it, and plain text for everything else, where the
/// address at least stays visible in the composed message.
final class SupportRecipientActivityItem: NSObject, UIActivityItemSource {
    private let email: String
    private let subject: String

    init(email: String, subject: String) {
        self.email = email
        self.subject = subject
        super.init()
    }

    private var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        mailtoURL ?? email
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        guard let mailtoURL else { return email }
        return activityType == .mail ? mailtoURL : email
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }

    /// Pre-fills the recipient in handlers that support it. The system calls this on the main
    /// thread while presenting, so it stays a plain value construction.
    func activityViewControllerShareRecipients(
        _ activityViewController: UIActivityViewController
    ) -> [INPerson] {
        let handle = INPersonHandle(value: email, type: .emailAddress)
        return [INPerson(personHandle: handle,
                         nameComponents: nil,
                         displayName: email,
                         image: nil,
                         contactIdentifier: nil,
                         customIdentifier: nil)]
    }
}
