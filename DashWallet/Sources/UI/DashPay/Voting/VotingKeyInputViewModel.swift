//
//  VotingKeyInputViewModel.swift
//  DashWallet
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

import Combine
import CryptoKit
import Foundation
import SwiftDashSDK

// MARK: - VotingKeyInputViewModel

/// Voting → "Enter your voting key": takes one masternode voting private key,
/// finds every active masternode that votes with it, and makes those nodes
/// votable from this wallet.
///
/// A narrower door into the same machinery as Governance → Masternodes → Add:
/// the SDK locator finds the nodes, the SDK registry tracks them, and the key
/// goes into the app's keychain vault, where `MasternodeVoterRegistry` picks it
/// up. Nothing new is persisted. This screen exists because that door is
/// advanced-mode only, and a masternode owner who only wants to vote should
/// not have to find it.
@MainActor
final class VotingKeyInputViewModel: ObservableObject {
    @Published var keyText = "" {
        // An error describes the text it was raised for; once that text
        // changes it would be describing something no longer on screen.
        didSet { if keyText != oldValue { error = nil } }
    }
    @Published private(set) var isVerifying = false
    @Published private(set) var error: String?

    private let vault: TrackedMasternodeKeyVaulting
    private let registry: MasternodeVoterRegistry

    /// Defaults are applied inside the `@MainActor` body; see `VotingViewModel`.
    init(
        vault: TrackedMasternodeKeyVaulting? = nil,
        registry: MasternodeVoterRegistry? = nil
    ) {
        self.vault = vault ?? TrackedMasternodeKeyVault()
        self.registry = registry ?? MasternodeVoterRegistry()
    }

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canVerify: Bool { !isVerifying && !trimmedKey.isEmpty }

    /// Check the key and, when it belongs to active masternodes this wallet
    /// cannot vote with yet, add it. Returns `true` once at least one node
    /// became votable; otherwise ``error`` says why not.
    func verifyAndAdd() async -> Bool {
        let key = trimmedKey
        guard !key.isEmpty, !isVerifying else { return false }
        error = nil

        let isMainnet = WalletEnvironment.network == .mainnet
        // Read the key locally first. The SDK locator only reports "can't read
        // that", and for a key typed by hand the useful answer is what is
        // wrong with it — an address, hex, the other network's key.
        if let problem = VotingKeyFormat.problem(with: key, isMainnet: isMainnet) {
            error = problem.message(isMainnet: isMainnet)
            return false
        }

        guard let manager = SwiftDashSDKHost.shared.manager else {
            error = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal")
            return false
        }

        isVerifying = true
        defer { isVerifying = false }

        let result: MasternodeLocateResult
        do {
            // Never `searchPlatform`: a voting key is on the masternode list
            // itself, and asking Platform would only reveal the key's hash to
            // a DAPI node for nothing.
            result = try await manager.locateMasternode(key, searchPlatform: false)
        } catch let sdkError as PlatformWalletError {
            switch sdkError {
            case .masternodeListUnavailable:
                error = NSLocalizedString(
                    "The masternode list is still syncing. Try again in a moment.",
                    comment: "Voting")
            case .invalidParameter:
                error = NSLocalizedString("You have entered an invalid key", comment: "Voting")
            default:
                error = sdkError.errorDescription ?? sdkError.localizedDescription
            }
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }

        // Only nodes this key is the VOTING key of. The locator also answers
        // to an owner key, and one of those would be tracked here and then
        // never vote. A PoSe-banned node is left out too: Platform refuses its
        // vote, and `MasternodeVoterRegistry` would not list it anyway.
        let votingMatches = result.matches.filter {
            $0.matchedBy == .key && $0.matchedKeys.contains(.voting) && $0.isValid
        }
        guard !votingMatches.isEmpty else {
            error = NSLocalizedString(
                "You have entered a key that is not associated to an active Masternode",
                comment: "Voting")
            return false
        }

        let votable = Set(registry.votableNodes().nodes.map(\.proTxHash))
        let notYetVotable = votingMatches.filter { !votable.contains($0.proTxHash) }
        // A node registered to a loaded wallet votes through that wallet's
        // derived key or not at all: the registry deliberately never lists it
        // as a tracked node, so storing a key for it here would claim a vote
        // that cannot happen.
        let addable = notYetVotable.filter { $0.inWalletId == nil }
        guard !addable.isEmpty else {
            error = notYetVotable.isEmpty
                ? NSLocalizedString("You have already entered this masternode key", comment: "Voting")
                : NSLocalizedString(
                    "This masternode is registered to a wallet in this app. Its voting key cannot be added separately.",
                    comment: "Voting")
            return false
        }

        // Every node sharing the key is added — an operator can point several
        // nodes at one voting key, and voting with only some of them would
        // under-count what this key controls. A failure stops the run but keeps
        // the nodes already added: each of those is complete and votes.
        var added = 0
        for match in addable {
            var trackedNow = false
            if !match.alreadyTracked {
                do {
                    try manager.trackMasternode(proTxHash: match.proTxHash, label: nil)
                    trackedNow = true
                } catch {
                    self.error = (error as? PlatformWalletError)?.errorDescription ?? error.localizedDescription
                    return added > 0
                }
            }
            guard vault.store(key, for: match.proTxHash, role: .voting) else {
                // Undo only what this attempt did: a node the user tracked
                // earlier keeps its row and whatever keys it had.
                if trackedNow {
                    _ = try? manager.untrackMasternode(proTxHash: match.proTxHash)
                }
                error = NSLocalizedString(
                    "Could not save a key to the keychain. Nothing was lost — try again.",
                    comment: "Add masternode")
                return added > 0
            }
            added += 1
        }

        keyText = ""
        return true
    }
}

// MARK: - VotingKeyFormat

/// What is wrong with a pasted voting key, when something is — the same
/// distinctions the Android wallet draws, so both apps answer a mistake the
/// same way.
enum VotingKeyProblem: Equatable {
    /// A valid WIF for the other network.
    case wrongNetwork
    /// A Dash address, not a key.
    case address
    case hexPrivateKey
    case hexPublicKey
    case tooShort
    /// Base58 characters, but the checksum does not add up — a mistyped key.
    case checksum
    /// A character Base58 does not use (`0`, `O`, `I`, `l`, punctuation…).
    case invalidCharacter
    case invalid

    func message(isMainnet: Bool) -> String {
        let example = isMainnet ? VotingKeyFormat.mainnetExample : VotingKeyFormat.testnetExample
        switch self {
        case .wrongNetwork:
            return String(
                format: isMainnet
                    ? NSLocalizedString(
                        "You have entered a key that is for testnet, but this is mainnet. It should look like this: %@",
                        comment: "Voting")
                    : NSLocalizedString(
                        "You have entered a key that is for mainnet, but this is testnet. It should look like this: %@",
                        comment: "Voting"),
                example)
        case .address:
            return String(
                format: NSLocalizedString(
                    "You have entered an address instead of a masternode voting private key. It should be in WIF format (%@)",
                    comment: "Voting"),
                example)
        case .hexPrivateKey, .hexPublicKey:
            return String(
                format: NSLocalizedString(
                    "You have entered a key in hex format, but it should be in WIF format (%@)",
                    comment: "Voting"),
                example)
        case .tooShort:
            return String(
                format: NSLocalizedString(
                    "You have entered a private key that is too short. Here is an example (%@)",
                    comment: "Voting"),
                example)
        case .checksum:
            return String(
                format: NSLocalizedString(
                    "You have entered a private key with some incorrect characters. Here is an example (%@)",
                    comment: "Voting"),
                example)
        case .invalidCharacter:
            return String(
                format: NSLocalizedString(
                    "You have entered a private key that has an invalid character. Here is an example (%@)",
                    comment: "Voting"),
                example)
        case .invalid:
            return NSLocalizedString("You have entered an invalid key", comment: "Voting")
        }
    }
}

enum VotingKeyFormat {
    /// Example keys shown in the error messages — Android's, so both apps show
    /// the same ones. Illustrations of the format, not keys of any node.
    static let mainnetExample = "XKm5koXHMm7UrVV3ki2pbGA8yZztiSR2F9x6ucEyCSuqTHBMjJix"
    static let testnetExample = "cUR2TrX4U6t6g9kRfDoBbwF2WRKBNjV3gK7HwTgQgmUUQCKXcT3N"

    /// WIF version bytes (`dashcore::PrivateKey::to_wif`). Devnet and regtest
    /// share testnet's.
    private static let mainnetVersion: UInt8 = 0xCC
    private static let testnetVersion: UInt8 = 0xEF

    /// `nil` when `text` is a well-formed WIF private key for this network.
    ///
    /// Well-formed only: whether a masternode votes with it is the locator's
    /// question. Hex is refused even though the signer could use it, because
    /// the voting key an owner holds — from `protx` or dashmate — is a WIF,
    /// and a 64-hex string is far more often something else pasted by mistake.
    static func problem(with text: String, isMainnet: Bool) -> VotingKeyProblem? {
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if text.unicodeScalars.allSatisfy(hexDigits.contains) {
            switch text.count {
            case 64: return .hexPrivateKey
            case 66, 130: return .hexPublicKey
            default: break
            }
        }

        guard let raw = ScriptAddressCodec.base58Decode(text) else { return .invalidCharacter }
        guard raw.count > 4 else { return .tooShort }

        let payload = Data(raw.prefix(raw.count - 4))
        let checksum = Data(raw.suffix(4))
        let digest = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))))
        guard digest.prefix(4) == checksum else {
            // 1 version + 32 key + 4 checksum: anything shorter cannot be a
            // key whatever its characters are.
            return raw.count < 37 ? .tooShort : .checksum
        }

        // Version byte + hash160.
        if payload.count == 21 { return .address }

        // Version + 32-byte key, plus the 0x01 flag of a compressed key.
        let isKeyShaped = payload.count == 33 || (payload.count == 34 && payload.last == 0x01)
        guard isKeyShaped else { return payload.count < 33 ? .tooShort : .invalid }

        let expected = isMainnet ? mainnetVersion : testnetVersion
        let other = isMainnet ? testnetVersion : mainnetVersion
        switch payload.first {
        case expected: return nil
        case other: return .wrongNetwork
        default: return .invalid
        }
    }
}
