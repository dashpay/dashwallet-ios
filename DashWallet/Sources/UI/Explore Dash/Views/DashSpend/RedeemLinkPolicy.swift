//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import Foundation

/// Rules for opening a gift card's redeem link: in the in-app browser, in the system browser, or not at all.
enum RedeemLinkPolicy {
    private static let redeemPath = "^/+gift-cards/[A-Za-z0-9_-]+/redeem$"
    private static let subframeOnlyURLs: Set<String> = ["about:blank", "about:srcdoc"]
    private static let webKitErrorDomain = "WebKitErrorDomain"
    private static let frameLoadInterruptedByPolicyChange = 102
    private static let httpsPort = 443

    /// The URL to load in the in-app browser, or nil when the link is not a redeem link on the CTX API host.
    static func inAppURL(_ link: String?, ctxBaseURL: String) -> URL? {
        // WebKit reads a backslash as a slash.
        guard let link, !link.contains("\\"),
              let parsed = parse(link),
              let ctxHost = parse(ctxBaseURL)?.host,
              parsed.components.scheme?.lowercased() == "https",
              parsed.host == ctxHost,
              parsed.components.percentEncodedUser == nil,
              parsed.components.port == nil || parsed.components.port == httpsPort else {
            return nil
        }

        let path = parsed.components.percentEncodedPath
        return path.range(of: redeemPath, options: .regularExpression) == nil ? nil : parsed.url
    }

    static func canOpenInApp(_ link: String?, ctxBaseURL: String) -> Bool {
        inAppURL(link, ctxBaseURL: ctxBaseURL) != nil
    }

    /// Whether the redeem screen is used for the link. It is not where the OS cannot refuse a page's
    /// file upload panel; the link then goes to the system browser.
    static func shouldOpenInApp(_ link: String?, ctxBaseURL: String, canRefuseUploads: Bool) -> Bool {
        canRefuseUploads && canOpenInApp(link, ctxBaseURL: ctxBaseURL)
    }

    static func isAllowedNavigation(_ url: String?, isMainFrame: Bool) -> Bool {
        guard let url else { return false }

        if subframeOnlyURLs.contains(url) {
            return !isMainFrame
        }
        return webURL(url)?.scheme?.lowercased() == "https"
    }

    /// The URL to hand to the system, or nil. Any http or https link Foundation reads is accepted when its
    /// host is written plainly, except across the CTX domain, where a link carries a bearer token: there
    /// plain http is refused and an https link has to pass `parse`.
    static func externalURL(_ link: String?, ctxBaseURL: String) -> URL? {
        guard let link, link == link.trimmingCharacters(in: .whitespacesAndNewlines),
              hasPlainHost(link),
              let url = webURL(link),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }

        // URL.host is percent-decoded, as a browser would read it.
        guard let host = url.host?.lowercased(),
              let ctxHost = parse(ctxBaseURL)?.host,
              isSameSite(host, ctxHost) else {
            return url
        }
        return scheme == "https" ? parse(link)?.url : nil
    }

    static func canOpenExternally(_ link: String?, ctxBaseURL: String) -> Bool {
        externalURL(link, ctxBaseURL: ctxBaseURL) != nil
    }

    /// Whether a failed load leaves no usable page, so the error state takes its place. With no page
    /// committed every failure does. Once a page has committed, only the first navigation's own failure
    /// does, and not its cancellation: WebKit reports a load replaced by the next one, or stopped by a
    /// policy decision, as a failure too. A later navigation that fails leaves the committed page, and
    /// what the user typed into it, in place.
    static func isFatalLoadFailure(_ error: Error, isFirstNavigation: Bool, hasCommittedPage: Bool) -> Bool {
        if !hasCommittedPage {
            return true
        }
        if !isFirstNavigation {
            return false
        }

        let error = error as NSError
        let isCancelled = error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        let isStoppedByPolicy = error.domain == webKitErrorDomain && error.code == frameLoadInterruptedByPolicyChange
        return !isCancelled && !isStoppedByPolicy
    }

    /// The whole host: the app ships no public-suffix list to cut it down to the registrable domain.
    static func displayHost(_ url: String?) -> String? {
        guard let url else { return nil }
        return webURL(url)?.host?.lowercased()
    }

    /// A browser decodes a percent-encoded host and maps some non-ASCII characters to a dot, so such a
    /// host could name the CTX domain without comparing equal to it. Both the text between "://" and
    /// the path and the host Foundation reads from it must be plain ASCII without "%".
    private static func hasPlainHost(_ link: String) -> Bool {
        guard let authorityStart = link.range(of: "://")?.upperBound,
              let host = URLComponents(string: link)?.encodedHost else {
            return false
        }
        let authority = link[authorityStart...].prefix { !"/?#".contains($0) }
        return isPlain(authority) && isPlain(host)
    }

    private static func isPlain<Text: StringProtocol>(_ text: Text) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII && $0 != "%" }
    }

    /// Pages name URLs that Foundation does not write back unchanged, so a URL the web view reports is
    /// read leniently; only links the app itself opens go through `parse`.
    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private struct ParsedLink {
        let url: URL
        let components: URLComponents
        let host: String
    }

    /// A web link is accepted only when URL writes it back unchanged and URLComponents reads the same
    /// parts from the string as from that URL, so the string that was checked is the string that is opened.
    private static func parse(_ link: String) -> ParsedLink? {
        guard link == link.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: link),
              let components = URLComponents(string: link),
              url.absoluteString == link,
              components == URLComponents(url: url, resolvingAgainstBaseURL: false),
              // A browser decodes a percent-encoded host, so it would not be the host compared here.
              let host = components.encodedHost?.lowercased(), !host.isEmpty, !host.contains("%") else {
            return nil
        }
        return ParsedLink(url: url, components: components, host: host)
    }

    private static func isSameSite(_ host: String, _ otherHost: String) -> Bool {
        let host = withoutTrailingDot(host)
        let site = lastTwoLabels(otherHost)
        return host == site || host.hasSuffix("." + site)
    }

    // Stands in for the registrable domain, which needs a public-suffix list the app does not ship.
    private static func lastTwoLabels(_ host: String) -> String {
        withoutTrailingDot(host).split(separator: ".").suffix(2).joined(separator: ".")
    }

    private static func withoutTrailingDot(_ host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }
}
