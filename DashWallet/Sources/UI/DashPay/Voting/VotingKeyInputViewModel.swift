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

// MARK: - VotingKeyImportOutcome

/// How a Verify tap ended.
enum VotingKeyImportOutcome: Equatable {
    /// Every node the key votes with is now votable.
    case added
    /// Some nodes were added and the rest failed or cannot be added here (they
    /// belong to a wallet in this app). The added ones are complete and vote,
    /// so the flow moves on — but the notice has to travel with it, or the
    /// user would go on voting without learning some nodes are missing.
    case partiallyAdded(notice: String)
    /// Nothing was added; ``VotingKeyInputViewModel/error`` says why.
    case failed
}

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
    private let tracker: @MainActor () -> VotingKeyMasternodeTracking?
    private let votableProTxHashes: @MainActor () -> Set<Data>

    /// Defaults are applied inside the `@MainActor` body; see `VotingViewModel`.
    /// `tracker` and `votableProTxHashes` are read on every Verify, not once:
    /// the SDK manager comes and goes with the wallet.
    init(
        vault: TrackedMasternodeKeyVaulting? = nil,
        registry: MasternodeVoterRegistry? = nil,
        tracker: (@MainActor () -> VotingKeyMasternodeTracking?)? = nil,
        votableProTxHashes: (@MainActor () -> Set<Data>)? = nil
    ) {
        self.vault = vault ?? TrackedMasternodeKeyVault()
        let registry = registry ?? MasternodeVoterRegistry()
        self.tracker = tracker ?? { SwiftDashSDKHost.shared.manager }
        self.votableProTxHashes = votableProTxHashes
            ?? { Set(registry.votableNodes().nodes.map(\.proTxHash)) }
    }

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canVerify: Bool { !isVerifying && !trimmedKey.isEmpty }

    /// Check the key and, when it belongs to active masternodes this wallet
    /// cannot vote with yet, add it. On `.failed`, ``error`` says why.
    func verifyAndAdd() async -> VotingKeyImportOutcome {
        let key = trimmedKey
        guard !key.isEmpty, !isVerifying else { return .failed }
        error = nil

        let isMainnet = WalletEnvironment.network == .mainnet
        // Read the key locally first. The SDK locator only reports "can't read
        // that", and for a key typed by hand the useful answer is what is
        // wrong with it — an address, hex, the other network's key.
        if let problem = VotingKeyFormat.problem(with: key, isMainnet: isMainnet) {
            error = problem.message(isMainnet: isMainnet)
            return .failed
        }

        guard let manager = tracker() else {
            error = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal")
            return .failed
        }

        isVerifying = true
        defer { isVerifying = false }

        let located: [VotingKeyLocatedNode]
        do {
            located = try await manager.locateVotingKeyNodes(key)
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
            return .failed
        } catch {
            self.error = error.localizedDescription
            return .failed
        }

        // Only nodes this key is the VOTING key of. The locator also answers
        // to an owner key, and one of those would be tracked here and then
        // never vote. A PoSe-banned node is left out too: Platform refuses its
        // vote, and `MasternodeVoterRegistry` would not list it anyway.
        let votingMatches = located.filter { $0.isVotingKeyMatch && $0.isValid }
        guard !votingMatches.isEmpty else {
            error = NSLocalizedString(
                "You have entered a key that is not associated to an active Masternode",
                comment: "Voting")
            return .failed
        }

        let votable = votableProTxHashes()
        let notYetVotable = votingMatches.filter { !votable.contains($0.proTxHash) }
        // A node registered to a loaded wallet votes through that wallet's
        // derived key or not at all: the registry deliberately never lists it
        // as a tracked node, so storing a key for it here would claim a vote
        // that cannot happen.
        let addable = notYetVotable.filter { !$0.isInLoadedWallet }
        let walletOwnedCount = notYetVotable.count - addable.count
        guard !addable.isEmpty else {
            error = notYetVotable.isEmpty
                ? NSLocalizedString("You have already entered this masternode key", comment: "Voting")
                : NSLocalizedString(
                    "This masternode is registered to a wallet in this app. Its voting key cannot be added separately.",
                    comment: "Voting")
            return .failed
        }

        // Every node sharing the key is added — an operator can point several
        // nodes at one voting key, and voting with only some of them would
        // under-count what this key controls. A failure stops the run but keeps
        // the nodes already added: each of those is complete and votes. Entering
        // the key again retries the rest — added nodes are votable by then and
        // drop out of `addable`.
        var added = 0
        var failure: String?
        for match in addable {
            var trackedNow = false
            if !match.alreadyTracked {
                do {
                    try manager.trackForVoting(proTxHash: match.proTxHash)
                    trackedNow = true
                } catch {
                    failure = (error as? PlatformWalletError)?.errorDescription ?? error.localizedDescription
                    break
                }
            }
            guard vault.store(key, for: match.proTxHash, role: .voting) else {
                // Undo only what this attempt did: a node the user tracked
                // earlier keeps its row and whatever keys it had.
                if trackedNow {
                    manager.untrackForVoting(proTxHash: match.proTxHash)
                }
                failure = NSLocalizedString(
                    "Could not save a key to the keychain. Nothing was lost — try again.",
                    comment: "Add masternode")
                break
            }
            added += 1
        }

        // Wallet-owned nodes are reported apart from `failure`: entering the
        // key again cannot add them, so they must never read as "try again",
        // and while they exist the import is not complete.
        let walletOwnedNote: String?
        switch walletOwnedCount {
        case 0:
            walletOwnedNote = nil
        case 1:
            walletOwnedNote = NSLocalizedString(
                "One masternode that votes with this key is registered to a wallet in this app and was not added. Its voting key cannot be added separately.",
                comment: "Voting")
        default:
            walletOwnedNote = String(
                format: NSLocalizedString(
                    "%d masternodes that vote with this key are registered to a wallet in this app and were not added. Their voting key cannot be added separately.",
                    comment: "Voting"),
                walletOwnedCount)
        }

        var retryPart: [String] = []
        if let failure {
            guard added > 0 else {
                error = ([failure] + [walletOwnedNote].compactMap { $0 }).joined(separator: "\n")
                return .failed
            }
            // Counted against `addable` only, so "the rest" is exactly what a
            // retry can add.
            retryPart = [
                String(
                    format: NSLocalizedString(
                        "Added %1$d of %2$d masternodes that vote with this key. Enter the key again to add the rest.",
                        comment: "Voting"),
                    added, addable.count),
                failure,
            ]
        }
        keyText = ""
        let notice = (retryPart + [walletOwnedNote].compactMap { $0 }).joined(separator: "\n")
        return notice.isEmpty ? .added : .partiallyAdded(notice: notice)
    }
}

// MARK: - VotingKeyMasternodeTracking

/// A node the locator matched, reduced to what the voting-key import decides
/// on. The SDK's `MasternodeLocateMatch` has no public initializer, so tests
/// could not build one; this can be.
struct VotingKeyLocatedNode: Equatable {
    /// 32 WIRE-order bytes, as `MasternodeLocateMatch.proTxHash`.
    let proTxHash: Data
    /// The key was matched as this node's VOTING key — not only as its owner
    /// key, and not by address or proTxHash.
    let isVotingKeyMatch: Bool
    /// `false` when PoSe-banned.
    let isValid: Bool
    /// One of a loaded wallet's own masternodes.
    let isInLoadedWallet: Bool
    let alreadyTracked: Bool
}

/// The SDK calls the voting-key import and removal make — a seam so tests can
/// stand in for `PlatformWalletManager`.
@MainActor
protocol VotingKeyMasternodeTracking: AnyObject {
    func locateVotingKeyNodes(_ key: String) async throws -> [VotingKeyLocatedNode]
    func trackForVoting(proTxHash: Data) throws
    /// Best-effort: a registry row left behind holds no key and cannot vote.
    func untrackForVoting(proTxHash: Data)
}

extension PlatformWalletManager: VotingKeyMasternodeTracking {
    func locateVotingKeyNodes(_ key: String) async throws -> [VotingKeyLocatedNode] {
        // Never `searchPlatform`: a voting key is on the masternode list
        // itself, and asking Platform would only reveal the key's hash to a
        // DAPI node for nothing.
        try await locateMasternode(key, searchPlatform: false).matches.map {
            VotingKeyLocatedNode(
                proTxHash: $0.proTxHash,
                isVotingKeyMatch: $0.matchedBy == .key && $0.matchedKeys.contains(.voting),
                isValid: $0.isValid,
                isInLoadedWallet: $0.inWalletId != nil,
                alreadyTracked: $0.alreadyTracked)
        }
    }

    func trackForVoting(proTxHash: Data) throws {
        try trackMasternode(proTxHash: proTxHash, label: nil)
    }

    func untrackForVoting(proTxHash: Data) {
        _ = try? untrackMasternode(proTxHash: proTxHash)
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
    /// A valid WIF for this network without the compression flag. The
    /// locator would match it — it honours the flag when hashing the key —
    /// but signing hands the SDK only the 32-byte secret, and the vote is
    /// signed as the COMPRESSED key's address: a different voter identity,
    /// which Platform refuses. So it is turned away before it is imported
    /// as a node that looks votable and never is.
    case uncompressed
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
        case .uncompressed:
            return String(
                format: NSLocalizedString(
                    "You have entered an uncompressed private key. This app can only vote with a compressed voting key. Here is an example (%@)",
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
    /// Base58 of 1 version + 32 key + 1 compression flag + 4 checksum bytes.
    static let maxWIFLength = 52

    /// `nil` when `text` is a well-formed compressed WIF private key for this
    /// network.
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

        // Nothing longer than a compressed WIF can be a key, and the Base58
        // decoder is quadratic: a long paste would stall the main actor for
        // seconds before being refused anyway.
        guard text.utf8.count <= maxWIFLength else { return .invalid }

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

        // Version + 32-byte key, plus the 0x01 flag of a compressed key. The
        // uncompressed shape is still recognised here, so it can be named
        // below rather than reported as unreadable.
        let isKeyShaped = payload.count == 33 || (payload.count == 34 && payload.last == 0x01)
        guard isKeyShaped else { return payload.count < 33 ? .tooShort : .invalid }

        let expected = isMainnet ? mainnetVersion : testnetVersion
        let other = isMainnet ? testnetVersion : mainnetVersion
        switch payload.first {
        case expected: return payload.count == 33 ? .uncompressed : nil
        case other: return .wrongNetwork
        default: return .invalid
        }
    }
}
