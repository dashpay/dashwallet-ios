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

import XCTest
@testable import dashpay

final class RedeemLinkPolicyTests: XCTestCase {
    private let prodBase = "https://spend.ctx.com/"
    private let stagingBase = "https://staging.spend.ctx.com/"
    private let prodLink = "https://spend.ctx.com/gift-cards/5f1c2d3e-0a1b-4c2d-8e3f-123456789abc/redeem?token=abc.def"

    private func canOpen(_ link: String?, base: String? = nil) -> Bool {
        RedeemLinkPolicy.canOpenInApp(link, ctxBaseURL: base ?? prodBase)
    }

    private func canLeave(_ link: String?, base: String? = nil) -> Bool {
        RedeemLinkPolicy.canOpenExternally(link, ctxBaseURL: base ?? prodBase)
    }

    // MARK: In-app entry

    func testCtxRedeemLinkOpensInApp() {
        XCTAssertTrue(canOpen(prodLink))
        XCTAssertTrue(canOpen("https://spend.ctx.com/gift-cards/abc_123/redeem"))
        XCTAssertTrue(canOpen("https://spend.ctx.com:443/gift-cards/abc/redeem"))
    }

    func testInAppURLIsTheLinkThatWasChecked() {
        XCTAssertEqual(RedeemLinkPolicy.inAppURL(prodLink, ctxBaseURL: prodBase)?.absoluteString, prodLink)
        XCTAssertNil(RedeemLinkPolicy.inAppURL("https://piggy.cards/claim/abc", ctxBaseURL: prodBase))
    }

    func testHostIsTakenFromTheConfiguredBaseURL() {
        let stagingLink = "https://staging.spend.ctx.com/gift-cards/abc/redeem?token=t"

        XCTAssertTrue(canOpen(stagingLink, base: stagingBase))
        XCTAssertFalse(canOpen(stagingLink, base: prodBase))
        XCTAssertFalse(canOpen(prodLink, base: stagingBase))
        XCTAssertFalse(canOpen(prodLink, base: "not a url"))
        XCTAssertFalse(canOpen("https:///gift-cards/abc/redeem", base: "https:///"))
        XCTAssertFalse(canOpen("https://:443/gift-cards/abc/redeem", base: "https://:443/"))
    }

    func testOtherHostsDoNotOpenInApp() {
        XCTAssertFalse(canOpen("https://claims.storedvalue.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com.evil.io/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://evilspend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com@evil.io/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com./gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend%2Ectx.com/gift-cards/abc/redeem"))
    }

    func testUserInfoOnTheCtxHostDoesNotOpenInApp() {
        XCTAssertFalse(canOpen("https://user@spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://:secret@spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://user:secret@spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://@spend.ctx.com/gift-cards/abc/redeem"))
    }

    func testOnlyHttpsOnTheDefaultPortOpensInApp() {
        XCTAssertFalse(canOpen("http://spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("http://spend.ctx.com:443/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com:8443/gift-cards/abc/redeem"))
    }

    func testHostAndSchemeCaseIsIgnoredPathCaseIsNot() {
        XCTAssertTrue(canOpen("HTTPS://SPEND.CTX.COM/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/GIFT-CARDS/abc/REDEEM"))
    }

    func testBackslashAnywhereDoesNotOpenInApp() {
        XCTAssertFalse(canOpen("https://spend.ctx.com\\gift-cards\\abc\\redeem"))
        XCTAssertFalse(canOpen("https:\\\\spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem?token=a\\b"))
    }

    func testCharactersWebKitWouldDropOrRewriteDoNotOpenInApp() {
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem?token=a\tb"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem?token=a\nb"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem?token=a b"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem?token=é"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc\u{0}/redeem"))
    }

    func testRepeatedLeadingSlashesStillOpenInApp() {
        XCTAssertTrue(canOpen("https://spend.ctx.com//gift-cards/abc/redeem?token=t"))
        XCTAssertFalse(canOpen("https://spend.ctx.com//api/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc//redeem"))
    }

    func testOtherPathsDoNotOpenInApp() {
        XCTAssertFalse(canOpen("https://spend.ctx.com/"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards//redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem/"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem/extra"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/api/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/a%2Fb/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem/../../../login"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/login?next=/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("https://spend.ctx.com/gift-cards/abc/redeem%0A"))
    }

    func testMissingOrMalformedLinksDoNotOpenInApp() {
        XCTAssertFalse(canOpen(nil))
        XCTAssertFalse(canOpen(""))
        XCTAssertFalse(canOpen("   "))
        XCTAssertFalse(canOpen("spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("//spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canOpen("javascript:alert(1)"))
    }

    func testSurroundingWhitespaceDoesNotOpenInApp() {
        XCTAssertFalse(canOpen(" \(prodLink)"))
        XCTAssertFalse(canOpen("\(prodLink) "))
        XCTAssertFalse(canOpen("\(prodLink)\n"))
    }

    // MARK: Navigation inside the browser

    func testNavigationHttpsIsAllowedToAnyHostInAnyFrame() {
        XCTAssertTrue(RedeemLinkPolicy.isAllowedNavigation("https://claims.storedvalue.com/claim?x=1", isMainFrame: true))
        XCTAssertTrue(RedeemLinkPolicy.isAllowedNavigation("https://www.merchant.example/redeem", isMainFrame: false))
        XCTAssertTrue(RedeemLinkPolicy.isAllowedNavigation("HTTPS://www.merchant.example/a?b=c|d", isMainFrame: true))
    }

    func testNavigationOtherSchemesAreBlockedInAnyFrame() {
        let blocked = [
            "http://claims.storedvalue.com/claim",
            "itms-apps://apps.apple.com/app/id1206647026",
            "dash:XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw?amount=1",
            "file:///var/mobile/Containers/Data/Application/wallet.log",
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "blob:https://claims.storedvalue.com/0f6e6c7e-4a3b-4f0e-9d53-0f8f4b6f6a11",
            "about:config",
            "about:blank#fragment",
            "https:///claim",
            "",
            "https",
        ]

        for url in blocked {
            XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: true), url)
            XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: false), url)
        }
        XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(nil, isMainFrame: true))
        XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(nil, isMainFrame: false))
    }

    func testNavigationBlankDocumentsAreAllowedInSubframesOnly() {
        for url in ["about:blank", "about:srcdoc"] {
            XCTAssertTrue(RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: false), url)
            XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: true), url)
        }
    }

    // MARK: Host line

    func testDisplayHostIsTheWholeHostInLowercase() {
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://claims.storedvalue.com/claim"), "claims.storedvalue.com")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://spend.ctx.com.evil.io/"), "spend.ctx.com.evil.io")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://gift.shop.merchant.co.uk/"), "gift.shop.merchant.co.uk")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://CLAIMS.StoredValue.com:8443/claim"), "claims.storedvalue.com")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://user@claims.storedvalue.com/claim"), "claims.storedvalue.com")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://xn--bcher-kva.de/"), "xn--bcher-kva.de")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://192.168.1.10/claim"), "192.168.1.10")
        XCTAssertEqual(RedeemLinkPolicy.displayHost("https://localhost/claim"), "localhost")
    }

    func testDisplayHostIsMissingWithoutAHost() {
        XCTAssertNil(RedeemLinkPolicy.displayHost("about:blank"))
        XCTAssertNil(RedeemLinkPolicy.displayHost("https:///claim"))
        XCTAssertNil(RedeemLinkPolicy.displayHost(nil))
    }

    // MARK: System browser

    func testExternalOpenHttpsGoesOutForAnyHost() {
        XCTAssertTrue(canLeave("https://piggy.cards/claim/abc"))
        XCTAssertTrue(canLeave(prodLink))
        XCTAssertTrue(canLeave("https://xn--bcher-kva.de/claim/abc"))
        XCTAssertTrue(canLeave("https://[2001:db8::1]/claim/abc"))
        XCTAssertEqual(RedeemLinkPolicy.externalURL(prodLink, ctxBaseURL: prodBase)?.absoluteString, prodLink)
    }

    func testExternalOpenHttpGoesOutOnlyOffTheCtxHost() {
        XCTAssertTrue(canLeave("http://piggy.cards/claim/abc"))
        XCTAssertTrue(canLeave("http://spend.ctx.com/gift-cards/abc/redeem", base: "not a url"))
        XCTAssertFalse(canLeave("http://spend.ctx.com/gift-cards/abc/redeem?token=t"))
        XCTAssertFalse(canLeave("HTTP://SPEND.CTX.COM/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://spend.ctx.com./gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://spend.ctx.com/gift-cards/abc/redeem", base: "https://spend.ctx.com./"))
    }

    func testExternalOpenHttpIsRefusedAcrossTheCtxDomain() {
        XCTAssertFalse(canLeave("http://spend.ctx.com/gift-cards/abc/redeem", base: stagingBase))
        XCTAssertFalse(canLeave("http://staging.spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://www.spend.ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://ctx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://staging.spend.ctx.com./x"))
        XCTAssertFalse(canLeave("http://spend%2Ectx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("http://SPEND.ctx.com/gift-cards/abc/redeem?token=a b"))
        XCTAssertFalse(canLeave("http://ctx.com/gift-cards/abc/redeem", base: "https://ctx.com./"))
    }

    func testExternalOpenHttpOnLookalikeDomainsIsNotTheCtxDomain() {
        XCTAssertTrue(canLeave("http://spend.ctx.com.evil.io/claim"))
        XCTAssertTrue(canLeave("http://evilctx.com/claim"))
        XCTAssertTrue(canLeave("http://ctx.com.au/claim"))
    }

    func testExternalOpenRefusesSurroundingWhitespace() {
        let claimLink = "https://piggy.cards/claim/abc"

        XCTAssertFalse(canLeave(" \(claimLink)"))
        XCTAssertFalse(canLeave("\(claimLink) "))
        XCTAssertFalse(canLeave("\(claimLink)\n"))
    }

    func testExternalOpenIsLimitedToWebLinks() {
        let refused = [
            "file:///var/mobile/card.html",
            "dash:XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw?amount=1",
            "dashwallet://pay?address=XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw",
            "pay:XdAUmwtig27HBG6WfYyHAzP8n6XC9jESEw",
            "javascript:alert(1)",
            "https:///claim",
            "https://:443/claim",
            "piggy.cards/claim/abc",
            "",
            "   ",
        ]

        for link in refused {
            XCTAssertFalse(canLeave(link), link)
        }
        XCTAssertFalse(canLeave(nil))
    }

    func testExternalOpenOffTheCtxDomainTakesWhatFoundationReads() {
        XCTAssertEqual(
            RedeemLinkPolicy.externalURL("https://piggy.cards/claim?code=a b", ctxBaseURL: prodBase)?.absoluteString,
            "https://piggy.cards/claim?code=a%20b"
        )
        XCTAssertTrue(canLeave("http://piggy.cards/claim?code=a b"))
        XCTAssertTrue(canLeave("https://piggy.cards/claim/é"))
        XCTAssertTrue(canLeave("HTTPS://Piggy.Cards/claim/abc"))
    }

    func testExternalOpenRefusesHostsABrowserWouldReadDifferently() {
        let refused = [
            "http://spend.ctx%E3%80%82com/gift-cards/abc/redeem",
            "http://spend%EF%BC%8Ectx.com/gift-cards/abc/redeem",
            "http://spend.ctx.com%E3%80%82/gift-cards/abc/redeem",
            "http://spend\u{3002}ctx.com/gift-cards/abc/redeem",
            "http://spend\u{FF0E}ctx.com/gift-cards/abc/redeem",
            "http://spend.ctx.com\u{3002}/gift-cards/abc/redeem",
            "https://spend.ctx%E3%80%82com/gift-cards/abc/redeem",
            "https://piggy%2Ecards/claim/abc",
            "https://piggy\u{3002}cards/claim/abc",
            "https://b\u{FC}cher.de/claim/abc",
            "http://user%40spend.ctx.com@piggy.cards/claim/abc",
        ]

        for link in refused {
            XCTAssertFalse(canLeave(link), link)
        }
        XCTAssertTrue(canLeave("https://xn--bcher-kva.de/claim/abc"))
        XCTAssertTrue(canLeave("http://piggy.cards/claim/%E3%80%82?next=a%2Eb\u{3002}c d"))
    }

    func testExternalOpenOnTheCtxDomainNeedsALinkThatIsOpenedUnchanged() {
        XCTAssertTrue(canLeave("https://staging.spend.ctx.com/gift-cards/abc/redeem?token=t"))
        XCTAssertTrue(canLeave("https://ctx.com/gift-card-agreement/"))
        XCTAssertFalse(canLeave("https://spend.ctx.com/gift-cards/abc/redeem?token=a b"))
        XCTAssertFalse(canLeave("https://spend.ctx.com/gift-cards/abc/redeem?token=é"))
        XCTAssertFalse(canLeave("https://spend%2Ectx.com/gift-cards/abc/redeem"))
        XCTAssertFalse(canLeave("https://www.spend.ctx.com./gift-cards/abc/redeem?token=a b"))
    }

    func testOtherAppLinksAreNeverANavigation() {
        let links = [
            "mailto:help@storedvalue.com",
            "TEL:+18005550100",
            "sms:+18005550100",
            "itms-apps://apps.apple.com/app/id1",
        ]

        for link in links {
            XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(link, isMainFrame: true), link)
            XCTAssertFalse(RedeemLinkPolicy.isAllowedNavigation(link, isMainFrame: false), link)
        }
    }

    // MARK: Failed loads

    private let connectionLost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
    private let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
    private let stoppedByPolicy = NSError(domain: "WebKitErrorDomain", code: 102)

    private func isFatal(_ error: NSError, committed: Bool, finished: Bool) -> Bool {
        RedeemLinkPolicy.isFatalLoadFailure(error, hasCommittedPage: committed, hasFinishedPage: finished)
    }

    func testAnyFailureBeforeTheFirstCommitIsFatal() {
        for error in [connectionLost, cancelled, stoppedByPolicy] {
            XCTAssertTrue(isFatal(error, committed: false, finished: false), "\(error.code)")
        }
    }

    func testADroppedConnectionBeforeTheFirstPageFinishesIsFatal() {
        XCTAssertTrue(isFatal(connectionLost, committed: true, finished: false))
        XCTAssertTrue(isFatal(NSError(domain: "WebKitErrorDomain", code: 101), committed: true, finished: false))
        XCTAssertTrue(isFatal(NSError(domain: "Other", code: NSURLErrorCancelled), committed: true, finished: false))
    }

    func testACancelledLoadKeepsACommittedPage() {
        XCTAssertFalse(isFatal(cancelled, committed: true, finished: false))
        XCTAssertFalse(isFatal(stoppedByPolicy, committed: true, finished: false))
    }

    func testNoFailureIsFatalOnceAPageHasFinished() {
        for error in [connectionLost, cancelled, stoppedByPolicy] {
            XCTAssertFalse(isFatal(error, committed: true, finished: true), "\(error.code)")
        }
    }
}
