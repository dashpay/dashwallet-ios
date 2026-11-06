//
//  CrowdNodeOwnershipTests.swift
//  DashWalletTests
//
//  Ticket 32026. The stored CrowdNode account address is checked against the
//  active wallet by a bounded BIP44 scan, and the answer decides whether the
//  account link is trusted, kept untouched, or destroyed. These pin the
//  tri-state: a scan that ran out of budget must never read as "not mine",
//  and an unproven address must never activate an account — the legacy
//  per-wallet key seeding can have copied it from another wallet.
//

import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class CrowdNodeOwnershipTests: XCTestCase {
    private struct LookupFailure: Error {}

    // Fixtures: the same hash160 encoded for two networks, plus a mainnet
    // P2SH — the address forms a real wallet can meet.
    private let mainnetAddress = "XhpXm8bjSKVGaXAKeGRNHDRg9W1o22PLJG"
    private let mainnetP2SHAddress = "7h9dhRvmgdg3cUng5kAsT3sn8mdd9eYYCz"
    private let testnetAddress = "yTT8n5gAss9LvG5sD7jmKEr2RnWAXScspP"

    private func lookup(isP2PKH: Bool, path: String?) -> CrowdNodeMessageSigner.OwnershipLookup {
        CrowdNodeMessageSigner.OwnershipLookup(
            isP2PKH: { _ in isP2PKH },
            derivationPath: { _ in path })
    }

    // MARK: ownsAddress — the tri-state

    func testScanFindingTheKeyProvesOwnership() {
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetAddress,
            using: lookup(isP2PKH: true, path: "m/44'/5'/0'/0/7"))
        XCTAssertEqual(owns, true)
    }

    func testScanExhaustionIsUnknownNotForeign() {
        // The address decodes fine; the scan simply did not find it. This case
        // stubs a generic miss and fixes neither an index nor a derivation
        // path — on the wallet in ticket 32026 the account address was most
        // likely missed because the scanned derivation paths do not reproduce
        // it, not because its index ran past the bound (that wallet had issued
        // only ~105 addresses). Either way the answer must be "unknown":
        // answering `false` tore a live link down.
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetAddress,
            using: lookup(isP2PKH: true, path: nil))
        XCTAssertNil(owns)
    }

    func testWalletNotUpIsUnknown() {
        // A relaunch validates prefs before the SDK wallet starts.
        XCTAssertNil(CrowdNodeMessageSigner.ownsAddress(mainnetAddress, using: nil))
    }

    func testUndecodableAddressIsForeign() {
        // The only route to `false`: the address cannot be a P2PKH address of
        // the running network, so no derivation index could ever produce it.
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetP2SHAddress,
            using: lookup(isP2PKH: false, path: "m/44'/5'/0'/0/7"))
        XCTAssertEqual(owns, false)
    }

    // MARK: which addresses reach the scan at all

    func testMainnetP2PKHAddressIsAccepted() {
        XCTAssertTrue(CrowdNodeMessageSigner.isP2PKH(mainnetAddress, network: .mainnet))
    }

    func testP2SHAddressIsRejectedOutright() {
        // CrowdNode account addresses are BIP44 receive addresses; a P2SH
        // address is not one and cannot be message-signed either.
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH(mainnetP2SHAddress, network: .mainnet))
    }

    func testAddressOfAnotherNetworkIsRejected() {
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH(testnetAddress, network: .mainnet))
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH(mainnetAddress, network: .testnet))
    }

    func testMalformedAddressIsRejected() {
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH("", network: .mainnet))
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH("not an address", network: .mainnet))
        // Valid base58, broken checksum.
        XCTAssertFalse(CrowdNodeMessageSigner.isP2PKH("XhpXm8bjSKVGaXAKeGRNHDRg9W1o22PLJH", network: .mainnet))
    }

    // MARK: what the restore does with each verdict

    func testProvenOwnershipTrustsTheStoredAccount() {
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: true), .trusted)
    }

    func testRefutedOwnershipResetsTheAccount() {
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: false), .alien)
    }

    func testUnknownOwnershipNeitherTrustsNorResets() {
        // The blocking review finding: `nil` used to be indistinguishable from
        // `true` at the restore's trust decision, so legacy state copied from
        // another wallet of the same network published `.linkedOnline` and
        // showed that wallet's CrowdNode balance under this one.
        let verdict = CrowdNode.storedAccountVerdict(ownership: Bool?.none)
        XCTAssertEqual(verdict, .unproven)
        XCTAssertNotEqual(verdict, .trusted, "an unproven address must not activate an account")
        XCTAssertNotEqual(verdict, .alien, "an unproven address must not destroy stored data")
    }

    // MARK: metadata stored beside the address

    // The second blocking finding: `validatePrefs` correctly PRESERVES an
    // unproven address, but the saved online state and cached balance stored
    // beside it come from the same legacy globals. Proving an address from this
    // wallet's history proves nothing about them.

    private let storedAddress = "XhpXm8bjSKVGaXAKeGRNHDRg9W1o22PLJH"
    private let otherAddress = "XwrJyFbdLBGuHhLBrTuUXQPGF7YXBhzRfN"

    func testProvenOwnershipKeepsTheMetadata() {
        XCTAssertTrue(CrowdNode.metadataSurvivesReconstruction(
            ownership: true, storedAddress: storedAddress, recoveredAddress: otherAddress),
            "a proven stored address is this wallet's, so its metadata is too")
    }

    func testUnprovenMetadataIsDroppedWhenAnotherAddressIsRecovered() {
        // Wallet B's own history recovers B's account; the stored address (and
        // therefore the balance and online state beside it) was A's.
        XCTAssertFalse(CrowdNode.metadataSurvivesReconstruction(
            ownership: Bool?.none, storedAddress: storedAddress, recoveredAddress: otherAddress))
    }

    func testUnprovenMetadataSurvivesWhenTheSameAddressIsRecovered() {
        // The history proves the address the metadata was stored against —
        // that is the account-specific evidence it was missing.
        XCTAssertTrue(CrowdNode.metadataSurvivesReconstruction(
            ownership: Bool?.none, storedAddress: storedAddress, recoveredAddress: storedAddress))
    }

    func testUnprovenMetadataIsDroppedWhenNothingIsRecovered() {
        XCTAssertFalse(CrowdNode.metadataSurvivesReconstruction(
            ownership: Bool?.none, storedAddress: storedAddress, recoveredAddress: nil))
    }

    func testMissingOrEmptyStoredAddressCarriesNoMetadata() {
        XCTAssertFalse(CrowdNode.metadataSurvivesReconstruction(
            ownership: Bool?.none, storedAddress: nil, recoveredAddress: otherAddress))
        XCTAssertFalse(CrowdNode.metadataSurvivesReconstruction(
            ownership: Bool?.none, storedAddress: "", recoveredAddress: ""),
            "an empty stored address must not match an empty recovered one")
    }

    func testRefutedOwnershipNeverKeepsMetadata() {
        XCTAssertFalse(CrowdNode.metadataSurvivesReconstruction(
            ownership: false, storedAddress: storedAddress, recoveredAddress: otherAddress))
    }

    // MARK: the two unknowns, told apart

    // Reviewer finding 3: `Bool?` flattened "the wallet isn't up" and "the scan
    // ran out" into one `nil`. Only the second is a verdict about this wallet,
    // and the restore's fruitless-pass memo must not be written on the first.

    func testWalletNotUpIsDistinctFromScanExhaustion() {
        XCTAssertEqual(
            CrowdNodeMessageSigner.ownership(of: mainnetAddress, using: nil),
            .walletUnavailable)
        XCTAssertEqual(
            CrowdNodeMessageSigner.ownership(
                of: mainnetAddress,
                using: lookup(isP2PKH: true, path: nil)),
            .notFoundWithinBound)
    }

    func testAWalletThatCannotAnswerIsUnavailableNotExhausted() {
        // A wallet without BIP-44 account 0 throws `notFound`. The scan never
        // ran, so that must not count as a checked miss.
        let failures: [Error] = [LookupFailure(), PlatformWalletError.notFound("no BIP-44 account 0")]
        for failure in failures {
            let failing = CrowdNodeMessageSigner.OwnershipLookup(
                isP2PKH: { _ in true },
                derivationPath: { _ in throw failure })
            let verdict = CrowdNodeMessageSigner.ownership(of: mainnetAddress, using: failing)
            XCTAssertEqual(verdict, .walletUnavailable, "\(failure)")
            XCTAssertFalse(verdict.wasChecked)
        }
    }

    func testForeignAddressIsRefusedBeforeTheWalletLookup() {
        let lookup = CrowdNodeMessageSigner.OwnershipLookup(
            isP2PKH: { _ in false },
            derivationPath: { _ in
                XCTFail("a foreign address must not reach the wallet's lookup")
                return nil
            })
        XCTAssertEqual(CrowdNodeMessageSigner.ownership(of: mainnetP2SHAddress, using: lookup), .foreign)
    }

    func testOnlyAWalletThatWasUpProducesACheckedVerdict() {
        XCTAssertFalse(CrowdNodeMessageSigner.Ownership.walletUnavailable.wasChecked,
                       "a pass built on this must not be memoized as fruitless")
        for verdict: CrowdNodeMessageSigner.Ownership in [.owned, .foreign, .notFoundWithinBound] {
            XCTAssertTrue(verdict.wasChecked)
        }
    }

    func testFourCaseVerdictAgreesWithTheBoolBridge() {
        // The bridge stays lossy on purpose; what it must never do is disagree
        // about trust or about destruction.
        XCTAssertEqual(
            CrowdNodeMessageSigner.ownership(
                of: mainnetAddress, using: lookup(isP2PKH: true, path: "m/44'/5'/0'/0/7")),
            .owned)
        XCTAssertEqual(
            CrowdNodeMessageSigner.ownsAddress(
                mainnetAddress, using: lookup(isP2PKH: true, path: "m/44'/5'/0'/0/7")),
            true)
        XCTAssertNil(CrowdNodeMessageSigner.ownsAddress(mainnetAddress, using: nil))
    }

    func testBothUnknownsLeaveTheStoredAccountUnproven() {
        // Neither may trust the account, and neither may destroy it.
        for verdict: CrowdNodeMessageSigner.Ownership in [.walletUnavailable, .notFoundWithinBound] {
            XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: verdict), .unproven)
        }
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: .owned), .trusted)
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: .foreign), .alien)
    }

    func testNoStoredAddressIsNotTheSameAsUnknownOwnership() {
        // `validatePrefs` returns nil for "nothing stored"; there is nothing to
        // trust and nothing to destroy.
        let verdict = CrowdNode.storedAccountVerdict(
            ownership: CrowdNodeMessageSigner.Ownership?.none)
        XCTAssertEqual(verdict, .unproven)
        XCTAssertNotEqual(verdict, .alien, "an absent address must never trigger a reset")
    }

    // MARK: which address the online restore acts on

    // The remaining reviewer finding lives in `getOnlineAccountAddress`, not in
    // the verdict: with trust withheld it reaches the API-confirmation branch
    // WITH a saved address present, which it never could before this change.
    // Both decisions it makes there are pinned here.

    func testAnUnprovenStoredAddressIsNeverTakenHoweverFarAlongItLooks() {
        // Wallet A's address and its `.done` copied into wallet B by the legacy
        // per-wallet key seeding. B must re-derive from its own history instead.
        for state: CrowdNode.OnlineAccountState in [.done, .creating, .signingUp, .linking, .validating] {
            XCTAssertFalse(CrowdNode.trustsStoredOnlineAddress(
                trustStoredAddress: false, storedAddress: storedAddress, state: state), "\(state)")
        }
    }

    func testAProvenStoredAddressIsTakenOnlyWithAnOnlineAccount() {
        XCTAssertTrue(CrowdNode.trustsStoredOnlineAddress(
            trustStoredAddress: true, storedAddress: storedAddress, state: .done))
        XCTAssertFalse(CrowdNode.trustsStoredOnlineAddress(
            trustStoredAddress: true, storedAddress: storedAddress, state: .none),
            "no online account to restore")
        XCTAssertFalse(CrowdNode.trustsStoredOnlineAddress(
            trustStoredAddress: true, storedAddress: nil, state: .done),
            "nothing stored to take")
    }

    func testRecoveringTheStoredAddressDoesNotWriteTheStateBackwards() {
        // The verdict is unproven on every launch for the population this
        // guard exists for, so a downgrade here would repeat forever and park
        // an offline account at `.linking`.
        XCTAssertFalse(CrowdNode.persistsLinkingDowngrade(
            confirmationAddress: storedAddress, storedAddress: storedAddress))
    }

    func testRecoveringADifferentAddressPersistsTheLinking() {
        // A genuinely different account: this wallet has only just found its
        // first evidence of it, and `.linking` is what that evidence supports.
        XCTAssertTrue(CrowdNode.persistsLinkingDowngrade(
            confirmationAddress: otherAddress, storedAddress: storedAddress))
        XCTAssertTrue(CrowdNode.persistsLinkingDowngrade(
            confirmationAddress: otherAddress, storedAddress: nil),
            "nothing stored, so nothing is being written backwards")
    }
}
