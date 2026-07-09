//
//  BuyReceiveFlowUITests.swift
//  DashWalletScreenshotsUITests
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

// MARK: - Support types

private struct CoinRow {
    let coinId: String
    let code: String
    let name: String
    let chain: String
    let refundAddress: String
}

private struct ResultRow {
    let coinId: String
    let code: String
    let chain: String
    let refundAddress: String
    let ok: Bool
    let uri: String
    let error: String
}

// MARK: - BuyReceiveFlowUITests

class BuyReceiveFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // No app.launch() here.
        // testBuyReceiveFlowUSDCArbitrum() calls launch() explicitly (fresh app start).
        // Attach-style tests (testFromBuyList, testAllCoinsFromBuyList) call app.activate()
        // to preserve the user's manual navigation state.
    }

    // MARK: - Full automated flow (launches app from scratch)

    // Drives: Home → Dash DEX shortcut → (PIN auth) → Buy Dash → USDC (Arbitrum) →
    // $6.5 → refund address → BuyReceive.
    //
    // Run:
    //   PATH=/tmp/fakebin:$PATH QA_WALLET_PIN=<pin> xcodebuild test \
    //     -workspace DashWallet.xcworkspace -scheme DashWalletScreenshotsUITests \
    //     -configuration Debug \
    //     -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' \
    //     ONLY_ACTIVE_ARCH=YES \
    //     -only-testing:DashWalletScreenshotsUITests/BuyReceiveFlowUITests/testBuyReceiveFlowUSDCArbitrum
    func testBuyReceiveFlowUSDCArbitrum() {
        setupSnapshot(app)
        app.launch()
        screenshot("01_home")

        let dashDexById = app.otherElements["shortcut_dash_dex"]
        let dashDexByLabel = app.staticTexts["Dash DEX"]
        if dashDexById.waitForExistence(timeout: 15) {
            dashDexById.tap()
        } else {
            XCTAssert(dashDexByLabel.waitForExistence(timeout: 5),
                      "Dash DEX shortcut not found by id or label")
            dashDexByLabel.tap()
        }
        screenshot("02a_after_shortcut_tap")

        handleAuthIfNeeded()
        screenshot("02b_after_auth")

        let buyDashButton = app.buttons.matching(identifier: "swap_portal_buy").firstMatch
        XCTAssert(buyDashButton.waitForExistence(timeout: 15),
                  "Buy Dash button not found — auth may have failed or SwapKit portal did not appear")
        buyDashButton.tap()
        screenshot("03_select_coin")

        let searchField = app.textFields.firstMatch
        XCTAssert(searchField.waitForExistence(timeout: 30), "Search field on SelectCoin did not appear")
        searchField.tap()
        searchField.typeText("USDC")

        let usdcArbButton = app.buttons.matching(identifier: "swap_coin_usdc_arb").firstMatch
        XCTAssert(usdcArbButton.waitForExistence(timeout: 30), "USDC (Arbitrum) coin not found")
        screenshot("04_coin_list_usdc")
        usdcArbButton.tap()

        let sixKey = app.buttons["6"]
        XCTAssert(sixKey.waitForExistence(timeout: 10), "Numeric keypad not found")
        sixKey.tap()
        let decimal = app.buttons["."].exists ? app.buttons["."] : app.buttons[","]
        decimal.tap()
        app.buttons["5"].tap()
        screenshot("05_enter_amount")

        let continueAmount = app.buttons["Continue"]
        XCTAssert(continueAmount.waitForExistence(timeout: 5), "Continue button not found")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: continueAmount)],
             timeout: 20)
        continueAmount.tap()

        let refundField = app.textFields.firstMatch
        XCTAssert(refundField.waitForExistence(timeout: 15), "Refund address field did not appear")
        screenshot("06_refund_address")
        refundField.tap()
        refundField.typeText("0x65f74AE7E89A2B53E844CB16d2D72C31fDCE4Bc4")

        let refundContinue = app.buttons.matching(identifier: "buy_refund_continue").firstMatch
        XCTAssert(refundContinue.waitForExistence(timeout: 5), "Refund Continue not found")
        refundContinue.tap()

        let qrImage = app.images.matching(identifier: "buy_receive_qr").firstMatch
        let qrLoaded = qrImage.waitForExistence(timeout: 30)
        screenshot("07_receive")
        XCTAssertTrue(qrLoaded,
                      "BuyReceive QR did not appear — createBuyOrder may have failed. See 07_receive.")
    }

    // MARK: - Attach-to-running-app: single coin

    // Attaches to an already-running app where the user has manually opened the Buy list
    // (Dash DEX → Buy Dash → SelectCoin). Drives SelectCoin → $6.5 → refund → BuyReceive.
    //
    // Run:
    //   PATH=/tmp/fakebin:$PATH xcodebuild test \
    //     -workspace DashWallet.xcworkspace -scheme DashWalletScreenshotsUITests \
    //     -configuration Debug \
    //     -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' \
    //     ONLY_ACTIVE_ARCH=YES \
    //     -only-testing:DashWalletScreenshotsUITests/BuyReceiveFlowUITests/testFromBuyList
    func testFromBuyList() {
        app.activate()

        let searchField = app.textFields.firstMatch
        let onBuyList = searchField.waitForExistence(timeout: 10)
            || app.buttons["swap_coin_usdc_arb"].waitForExistence(timeout: 5)
        XCTAssertTrue(
            onBuyList,
            "Not on the Buy list after activate() — navigate to Dash DEX → Buy Dash → coin list first, " +
            "or the test session reset the app state (then we need a launch-arg deep link)."
        )
        screenshot("05_coin_list")

        if searchField.exists { searchField.tap(); searchField.typeText("USDC") }
        let usdcArb = app.buttons["swap_coin_usdc_arb"].firstMatch
        XCTAssertTrue(usdcArb.waitForExistence(timeout: 20), "USDC (Arbitrum) not found in list")
        usdcArb.tap()

        let six = app.buttons["6"]
        XCTAssertTrue(six.waitForExistence(timeout: 10), "Numeric keypad not found")
        six.tap()
        let decimal = app.buttons["."].exists ? app.buttons["."] : app.buttons[","]
        decimal.tap()
        app.buttons["5"].tap()
        screenshot("06_enter_amount")

        let cont = app.buttons["Continue"].firstMatch
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue not found")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: cont)], timeout: 20)
        cont.tap()

        let refund = app.textFields.firstMatch
        XCTAssertTrue(refund.waitForExistence(timeout: 15),
                      "Refund field not found — quote validation may have failed (see 06_enter_amount)")
        screenshot("07_refund_address")
        refund.tap()
        refund.typeText("0x65f74AE7E89A2B53E844CB16d2D72C31fDCE4Bc4")

        let refundContinue = app.buttons["buy_refund_continue"].firstMatch
        XCTAssertTrue(refundContinue.waitForExistence(timeout: 5), "Refund Continue not found")
        refundContinue.tap()

        let qr = app.images["buy_receive_qr"].firstMatch
        let qrLoaded = qr.waitForExistence(timeout: 30)
        screenshot("08_receive")
        XCTAssertTrue(qrLoaded,
                      "BuyReceive QR did not appear within 30 s — see 08_receive for the error state.")
    }

    // MARK: - Attach-to-running-app: all coins (data-driven)

    // Reads refund-addresses.csv from the test bundle. For each row with a non-empty refund_address,
    // drives the full SelectCoin → amount → refund → BuyReceive flow and collects:
    //   - <coin_id>__receive — full-screen screenshot of the receive screen
    //   - <coin_id>__qr      — cropped QR image
    //   - <coin_id>__error   — screenshot of the error state (when QR never appears)
    //   - results.csv        — aggregated outcome table
    //
    // Never asserts hard inside the coin loop — one failure records an error and moves on.
    // Prerequisites: app is running, user has opened Dash DEX → Buy Dash → coin list.
    //
    // Run:
    //   PATH=/tmp/fakebin:$PATH xcodebuild test \
    //     -workspace DashWallet.xcworkspace -scheme DashWalletScreenshotsUITests \
    //     -configuration Debug \
    //     -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' \
    //     ONLY_ACTIVE_ARCH=YES \
    //     -only-testing:DashWalletScreenshotsUITests/BuyReceiveFlowUITests/testAllCoinsFromBuyList
    func testAllCoinsFromBuyList() {
        continueAfterFailure = true
        app.activate()

        let coins = loadRefundAddresses()
        guard !coins.isEmpty else {
            XCTFail("refund-addresses.csv is empty or not found in the test bundle")
            return
        }

        var results: [ResultRow] = []

        for (index, coin) in coins.enumerated() {
            print("[\(index + 1)/\(coins.count)] Processing \(coin.coinId) (\(coin.code)/\(coin.chain))")

            // 1. Ensure we're on the Buy list (SelectCoin)
            guard ensureOnBuyList() else {
                XCTFail("Cannot return to Buy list after \(results.count) coins — aborting run")
                break
            }

            // 2. Clear search, filter by code, tap the coin button
            let searchField = app.textFields.firstMatch
            clearSearchField(searchField)
            searchField.typeText(coin.code)

            let coinButton = app.buttons["swap_coin_\(coin.coinId)"].firstMatch
            guard coinButton.waitForExistence(timeout: 15) else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "coin not in list"))
                // Clear the search field so coin cells reappear — we're still on the Buy list,
                // just showing an empty filtered view. Tapping back would incorrectly exit it.
                clearSearchField(searchField)
                continue
            }
            coinButton.tap()

            // 3. Switch to USD mode, enter 6.5
            let usdButton = app.buttons["USD"].firstMatch
            if usdButton.waitForExistence(timeout: 5) { usdButton.tap() }

            let sixKey = app.buttons["6"]
            guard sixKey.waitForExistence(timeout: 10) else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "keypad not found"))
                _ = ensureOnBuyList()
                continue
            }
            sixKey.tap()
            let decimalKey = app.buttons["."].exists ? app.buttons["."] : app.buttons[","]
            decimalKey.tap()
            app.buttons["5"].tap()

            // Wait for Continue to become enabled (rate fetch), then tap
            let contButton = app.buttons["Continue"].firstMatch
            guard contButton.waitForExistence(timeout: 5) else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "Continue button not found"))
                _ = ensureOnBuyList()
                continue
            }

            let contEnabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                          evaluatedWith: contButton)
            let contWait = XCTWaiter().wait(for: [contEnabled], timeout: 20)
            guard contWait == .completed else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "Continue never enabled — rate timeout"))
                _ = ensureOnBuyList()
                continue
            }
            contButton.tap()

            // 4. Refund address
            let refundField = app.textFields.firstMatch
            guard refundField.waitForExistence(timeout: 15) else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "Refund field not found (quote failed)"))
                _ = ensureOnBuyList()
                continue
            }
            refundField.tap()
            refundField.typeText(coin.refundAddress)

            let refundContinue = app.buttons["buy_refund_continue"].firstMatch
            guard refundContinue.waitForExistence(timeout: 5) else {
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: "Refund Continue not found"))
                _ = ensureOnBuyList()
                continue
            }
            refundContinue.tap()

            // 5. BuyReceive — wait for QR, collect screenshots and URI
            let qrImage = app.images["buy_receive_qr"].firstMatch
            let qrOk = qrImage.waitForExistence(timeout: 30)

            if qrOk {
                addScreenshot(XCUIScreen.main.screenshot(), name: "\(coin.coinId)__receive")
                addScreenshot(qrImage.screenshot(), name: "\(coin.coinId)__qr")
                let uri = extractURI()
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: true, uri: uri, error: ""))
            } else {
                addScreenshot(XCUIScreen.main.screenshot(), name: "\(coin.coinId)__error")
                let errorText = readVisibleError()
                results.append(ResultRow(coinId: coin.coinId, code: coin.code, chain: coin.chain,
                                         refundAddress: coin.refundAddress,
                                         ok: false, uri: "", error: errorText))
            }

            // 6. Recover to Buy list for the next coin
            _ = ensureOnBuyList()
        }

        // Attach results.csv
        let csv = buildResultsCSV(results)
        let attachment = XCTAttachment(string: csv)
        attachment.name = "results.csv"
        attachment.lifetime = .keepAlways
        add(attachment)

        let okCount = results.filter { $0.ok }.count
        print("testAllCoinsFromBuyList: \(results.count) coins processed — \(okCount) ok, \(results.count - okCount) failed")
    }

    // MARK: - Auth handling (used by testBuyReceiveFlowUSDCArbitrum)

    private func handleAuthIfNeeded() {
        let buyDash = app.buttons.matching(identifier: "swap_portal_buy").firstMatch
        if buyDash.waitForExistence(timeout: 4) { return }

        let pin = ProcessInfo.processInfo.environment["QA_WALLET_PIN"] ?? ""
        guard !pin.isEmpty else {
            XCTFail("Auth dialog appeared but QA_WALLET_PIN is not set. " +
                    "Pass it as: QA_WALLET_PIN=<pin> xcodebuild test …")
            return
        }

        for char in pin {
            let digit = String(char)
            let byStaticText = app.staticTexts[digit].firstMatch
            let byButton = app.buttons[digit].firstMatch
            if byStaticText.waitForExistence(timeout: 5) {
                byStaticText.tap()
            } else if byButton.waitForExistence(timeout: 2) {
                byButton.tap()
            } else {
                XCTFail("PIN digit '\(digit)' not found — see screenshot 02a for the auth UI layout")
                return
            }
        }

        let okButton = app.alerts.firstMatch.buttons.firstMatch
        if okButton.waitForExistence(timeout: 2) { okButton.tap() }
    }

    // MARK: - Navigation helpers

    /// True only on the SelectCoin (Buy list) screen — detected by a `swap_coin_*` cell,
    /// which the refund/amount/receive screens do not have. (A text field is NOT a reliable
    /// marker: the Refund screen also has one.)
    private func onBuyList(timeout: TimeInterval = 0) -> Bool {
        let cell = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'swap_coin_'"))
            .firstMatch
        return timeout > 0 ? cell.waitForExistence(timeout: timeout) : cell.exists
    }

    /// Taps navigationbar-back until the SelectCoin (Buy list) screen is shown again.
    /// Returns false only if we've exhausted taps and still aren't on the Buy list.
    @discardableResult
    private func ensureOnBuyList(maxTaps: Int = 6) -> Bool {
        if onBuyList(timeout: 3) { return true }
        for _ in 0..<maxTaps {
            // Dismiss any stray alert first (e.g. an error dialog) so back isn't swallowed.
            let alertOK = app.alerts.firstMatch.buttons.firstMatch
            if alertOK.exists { alertOK.tap() }

            let back = app.buttons["navigationbar-back"].firstMatch
            guard back.exists else { break }
            back.tap()
            if onBuyList(timeout: 3) { return true }
        }
        return onBuyList()
    }

    /// Clears the search field by deleting its current content character by character.
    private func clearSearchField(_ field: XCUIElement) {
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap()
        let currentText = field.value as? String ?? ""
        guard !currentText.isEmpty else { return }
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentText.count)
        field.typeText(deletes)
    }

    // MARK: - Data extraction helpers

    /// Reads the URI from the BuyReceive screen by scanning staticText labels for known URI schemes.
    private func extractURI() -> String {
        let schemes = ["ethereum:", "bitcoin:", "solana:", "sui:", "web+cardano:",
                       "bitcoincash:", "dash:", "dogecoin:", "litecoin:", "0x"]
        for el in app.staticTexts.allElementsBoundByIndex {
            let label = el.label
            if schemes.contains(where: { label.hasPrefix($0) }) { return label }
        }
        return ""
    }

    /// Collects the first few non-empty staticText labels as an error description.
    private func readVisibleError() -> String {
        app.staticTexts.allElementsBoundByIndex
            .compactMap { $0.label.isEmpty ? nil : $0.label }
            .prefix(5)
            .joined(separator: " | ")
    }

    // MARK: - CSV helpers

    /// Parses refund-addresses.csv bundled into the test target.
    /// Format: semicolon-delimited, UTF-8 with optional BOM, CRLF or LF line endings.
    /// Skips the header row and any row where refund_address is empty.
    private func loadRefundAddresses() -> [CoinRow] {
        guard let url = Bundle(for: Self.self).url(forResource: "refund-addresses", withExtension: "csv"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("refund-addresses.csv not found in test bundle — add it as a Resources file")
            return []
        }

        let content = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let lines = content.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }

        return lines.dropFirst().compactMap { line -> CoinRow? in
            let fields = line.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 5 else { return nil }
            let refundAddress = fields[4]
            guard !refundAddress.isEmpty else { return nil }
            return CoinRow(coinId: fields[0], code: fields[1], name: fields[2],
                           chain: fields[3], refundAddress: refundAddress)
        }
    }

    private func buildResultsCSV(_ rows: [ResultRow]) -> String {
        var lines = ["coin_id,code,chain,refund_address,ok,uri,error"]
        for r in rows {
            let escape: (String) -> String = { s in
                s.contains(",") || s.contains("\"") || s.contains("\n")
                    ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
                    : s
            }
            lines.append([r.coinId, r.code, r.chain, r.refundAddress,
                          r.ok ? "true" : "false",
                          escape(r.uri), escape(r.error)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Screenshot helpers

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func addScreenshot(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
