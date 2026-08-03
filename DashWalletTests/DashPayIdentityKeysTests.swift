//
//  DashPayIdentityKeysTests.swift
//  DashWalletTests
//

import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

final class DashPayIdentityKeysTests: XCTestCase {

    func testRegistrationSpecificationsMatchDashPayContractPolicy() {
        let specifications = DWDashPayIdentityKeys.registrationSpecifications(firstKeyId: 4)

        XCTAssertEqual(specifications.count, 2)
        XCTAssertEqual(specifications.map(\.keyId), [4, 5])
        XCTAssertEqual(specifications.map(\.purpose), [.encryption, .decryption])
        XCTAssertTrue(specifications.allSatisfy { $0.keyType == .ecdsaSecp256k1 })
        XCTAssertTrue(specifications.allSatisfy { $0.securityLevel == .medium })
        XCTAssertTrue(specifications.allSatisfy {
            $0.contractBounds == .singleContractDocumentType(
                id: DWDashPayIdentityKeys.dashPayContractId,
                documentTypeName: "contactRequest")
        })
    }

    func testRecipientWithBothKeysIsEligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .encryption),
                key(purpose: .decryption),
            ]),
            true)
    }

    func testEncryptionOnlyMobileRecipientIsEligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .encryption),
            ]),
            true)
    }

    func testDecryptionOnlyRecipientIsEligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .decryption),
            ]),
            true)
    }

    func testRecipientWithNeitherCompatiblePurposeIsIneligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .authentication),
                key(purpose: .transfer),
            ]),
            false)
    }

    func testDisabledCompatibleKeyIsIneligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .encryption, disabledAt: 42),
            ]),
            false)
    }

    func testNonECDSACompatiblePurposeIsIneligible() {
        XCTAssertEqual(
            DWDashPayIdentityKeys.recipientEligibility(from: [
                key(purpose: .decryption, keyType: .bls12_381),
            ]),
            false)
    }

    func testUnavailableQueryRemainsUnknown() {
        XCTAssertNil(DWDashPayIdentityKeys.recipientEligibility(from: nil))
    }

    private func key(
        purpose: KeyPurpose,
        keyType: KeyType = .ecdsaSecp256k1,
        disabledAt: Int? = nil
    ) -> [String: Any] {
        var key: [String: Any] = [
            "purpose": Int(purpose.rawValue),
            "type": Int(keyType.rawValue),
        ]
        if let disabledAt {
            key["disabledAt"] = disabledAt
        }
        return key
    }
}
