import CryptoKit
import Foundation
import SwiftDashSDK

/// The App Connect request v2 login (Yappr `docs/APP_CONNECT_PROFILE.md`):
/// the rules a wallet applies between decoding a request
/// (`AppConnectRequest`) and registering the keys it names. Pure, like the
/// rest of `AppConnect`; `PlatformDashConnectDataSource` owns the Platform
/// calls and their order.
extension AppConnect {
    // MARK: Limits (profile wallet rule 5)

    /// The most budget the wallet grants a key the app proposes a budget
    /// for. A binding that asks for none gets none, and the sheet says the
    /// key can spend without a limit.
    static let v2BudgetCapCredits: UInt64 = 5 * PlatformCreditsFormatter.creditsPerDash
    /// The longest a key the wallet grants may live.
    static let v2LifetimeCap: TimeInterval = 365 * 24 * 60 * 60
    /// The lifetime a key gets when its binding asks for no expiry, so every
    /// auth key carries a limit.
    static let v2DefaultLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// The DashPay contract, the same id on every network.
    static let dashPayContractId = "Bwr4WHCPz5rFVAD87RqTs3izo4zpzwsEdKPWUT1NS1C7"
    /// Profile wallet rule 3: the only document types on a contract the app
    /// does not own that a binding may name. Never DashPay `contactRequest`,
    /// never DPNS.
    static let allowedForeignDocumentTypes: Set<String> = ["\(dashPayContractId)/profile"]
    /// Platform's system contracts (dashpay/platform `data-contracts`), the
    /// same ids on every network. None of them is an app: a request naming
    /// one as its app, or binding a key to one, is refused, except for the
    /// document types allowlisted above.
    static let systemContractIds: Set<String> = [
        "4fJLR2GYTPFdomuTVvNy3VRrvWgvkKPzqehEBpNf2nk6", // withdrawals
        "rUnsWrFu3PKyRMGk2mxmZVBPbQuZx2qtHeFjURoQevX", // masternode reward shares
        "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec", // DPNS
        dashPayContractId,
        "7CSFGeF4WNzgDmx94zwvHkYaG3Dx4XEe5LFsFgJswLbm", // wallet utils
        "43gujrzZgXqcKBiScLa4T8XTDnRhenR9BLx8GWVHjPxF", // token history
        "BsjE6tQxG47wffZCRQCovFx5rYrAYYC3rTVRWKro27LA", // keyword search
        "6voHRaoiPcfmMhbqCA9dixH98xcgPQ9UEcuaXjpVu3LD", // document history
        contractId, // App Connect
        "EG7RGfV8fDTayC2FyVr8HwdpJh3fXDbVztcfE94UmN88", // moderation charters
    ]

    // MARK: What an approval grants

    /// One auth key the approval registers, with the limits the wallet
    /// settled on: the app's proposal, clamped.
    struct AuthGrant: Equatable {
        /// The binding's position in the request. It is part of the key's
        /// derivation, so the key does not depend on what else is granted.
        let bindingIndex: Int
        let binding: AppConnectRequest.AuthBinding
        /// Set exactly when the binding asked for a budget.
        let totalBudget: UInt64?
        /// Block time in milliseconds. Always set.
        let expiresAt: UInt64

        var securityLevel: SecurityLevel {
            binding.securityLevel == .critical ? .critical : .high
        }

        /// The bound the key is registered with, as the store records it.
        var storedBound: StoredBound {
            switch binding.kind {
            case .singleContract: return .singleContract(binding.id)
            case .documentType: return .documentType(contractId: binding.id, name: binding.documentTypeName ?? "")
            case .contractGroup: return .contractGroup(binding.id)
            }
        }

        var contractBounds: ManagedPlatformWallet.ContractBounds {
            switch binding.kind {
            case .singleContract:
                return .singleContract(id: binding.id)
            case .documentType:
                return .singleContractDocumentType(id: binding.id, documentTypeName: binding.documentTypeName ?? "")
            case .contractGroup:
                return .contractGroup(id: binding.id)
            }
        }
    }

    /// One encryption (or decryption) key the response carries: the
    /// identity's key for the app, shared by every device.
    struct EncryptionGrant: Equatable {
        let bindingIndex: Int
        let binding: AppConnectRequest.EncryptionBinding

        var keyPurpose: KeyPurpose {
            binding.purpose == .encryption ? .encryption : .decryption
        }

        var connectPurpose: ManagedPlatformWallet.ConnectKeyPurpose {
            binding.purpose == .encryption ? .encryption : .decryption
        }
    }

    /// What approving a v2 request gives the app, as the approval sheet
    /// shows it. The keys are registered with exactly these terms.
    struct GrantPlan: Equatable {
        let appId: Data
        /// `hash160(appEphPub)`: names the request the plan was made for.
        let appEphemeralPubKeyHash: Data
        let auth: [AuthGrant]
        let encryption: [EncryptionGrant]
        let connectionId: Data?
        let identityHint: Data?
        /// Milliseconds since the epoch.
        let createdAt: UInt64
        /// Where the wallet returns when it is done; shown on the sheet.
        let callbackHost: String?
        /// The app's website in the wallet's brand map, or nil for an app the
        /// wallet does not know: then the name on the sheet is the one the
        /// request gives.
        var brandHost: String? = nil
        /// The groups among the bindings that have administrators besides
        /// their owner, as Platform proves them. Each administrator can add
        /// contracts of its own to the group, and a group key acts in every
        /// contract of the group when it signs, not only in those it had
        /// when it was granted.
        var administeredGroupIds: Set<Data> = []
        /// How the app's contract keeps the current key of each encryption
        /// purpose asked, as Platform proves the contract.
        var currentKeyRules: [KeyPurpose: CurrentKeyRule] = [:]

        /// The largest budget among the keys, for the summary line.
        var totalBudget: UInt64? {
            auth.compactMap(\.totalBudget).max()
        }

        /// The latest expiry among the keys.
        var expiresAt: UInt64? {
            auth.map(\.expiresAt).max()
        }
    }

    /// The `ac=` statuses of the profile's callback.
    enum CallbackStatus: String {
        case ok
        case declined
        case stale
        case unsupported
        case invalid
        case failed
    }

    /// A v2 request the wallet does not answer, with the status its callback
    /// reports.
    struct Refusal: LocalizedError, Equatable {
        let status: CallbackStatus
        let reason: String

        var errorDescription: String? { reason }

        init(_ status: CallbackStatus, _ reason: String) {
            self.status = status
            self.reason = reason
        }

        init(_ error: AppConnectRequestError) {
            switch error {
            case .unsupported(let reason): self.init(.unsupported, reason)
            case .invalid(let reason): self.init(.invalid, reason)
            }
        }
    }

    /// The plan for `uri` at `now`: every binding granted, the proposals
    /// clamped to the caps. A wallet may lower a proposal but must never drop
    /// a limit the app asked for, and every key gets an expiry.
    ///
    /// A renewal (`MODE = 1`) is answered as a new login carrying the same
    /// connection id, which supersedes the old keys (the profile's phase-1
    /// renewal); raising the limits of existing keys is not implemented.
    static func grantPlan(for uri: AppConnectUri, now: Date) throws -> GrantPlan {
        let request = uri.request
        switch request.age(now: now) {
        case .fresh: break
        case .stale: throw Refusal(.stale, NSLocalizedString(
                "The sign-in request is more than 10 minutes old.",
                comment: "DashConnect App Connect v2"))
        case .future: throw Refusal(.stale, NSLocalizedString(
                "The sign-in request is dated in the future. Check this device's clock.",
                comment: "DashConnect App Connect v2"))
        }
        let nowMilliseconds = milliseconds(now)
        let auth = try request.authBindings.enumerated().map { index, binding -> AuthGrant in
            if let expiresAt = binding.expiresAt, expiresAt <= nowMilliseconds {
                throw Refusal(.invalid, NSLocalizedString(
                "The app asks for a key that has already expired.",
                comment: "DashConnect App Connect v2"))
            }
            return AuthGrant(
                bindingIndex: index,
                binding: binding,
                totalBudget: binding.totalBudget.map { min($0, v2BudgetCapCredits) },
                expiresAt: binding.expiresAt.map { min($0, milliseconds(now.addingTimeInterval(v2LifetimeCap))) }
                    ?? milliseconds(now.addingTimeInterval(v2DefaultLifetime))
            )
        }
        let encryption = try request.encryptionBindings.enumerated().map { index, binding -> EncryptionGrant in
            // Wallet rule 3: the identity's encryption key for the app lives
            // on the app's own contract.
            guard binding.contractId == request.appId else {
                throw Refusal(.invalid, NSLocalizedString(
                "The app asks for an encryption key on a contract other than its own.",
                comment: "DashConnect App Connect v2"))
            }
            return EncryptionGrant(bindingIndex: index, binding: binding)
        }
        return GrantPlan(
            appId: request.appId,
            appEphemeralPubKeyHash: try KeyExchangeCrypto.hash160(request.appEphemeralPubKey),
            auth: auth,
            encryption: encryption,
            connectionId: request.connectionId,
            identityHint: request.identityHint,
            createdAt: request.createdAt,
            callbackHost: uri.callback?.host
        )
    }

    /// The profile's callback rule for an app in the wallet's brand map: a
    /// request whose `cb` is on a host that is not the app's is refused.
    /// The sheet would be branded as the app and return somewhere else, and
    /// the host is the user's main phishing signal. A request without `cb`
    /// is not refused, the sheet warns instead
    /// (`ApproveConnectionSheet.originWarning`).
    ///
    /// The request itself proves nothing about where it came from: anyone
    /// can put the app's id and the app's host in a QR code. What the wallet
    /// can check is that what it shows agrees with itself.
    static func callbackRefusal(callbackHost: String?, brandHost: String?) -> Refusal? {
        guard let brandHost, let callbackHost, !isHost(callbackHost, of: brandHost) else { return nil }
        return Refusal(.invalid, String(
            format: NSLocalizedString(
                "This request would return to %@, which is not the app's website.",
                comment: "DashConnect App Connect v2: the placeholder is a website, e.g. yap.pr"),
            callbackHost))
    }

    /// Whether `host` is `brandHost` or one of its subdomains. Both are
    /// lowercase DNS names: the callback parser takes no other host.
    static func isHost(_ host: String, of brandHost: String) -> Bool {
        host == brandHost || host.hasSuffix("." + brandHost)
    }

    /// Wallet rule 3, owner consistency, from what the network says:
    /// - a contract group must be owned by the owner of `appId`;
    /// - a contract, or a document type's contract, must be owned by that
    ///   owner, unless the document type is on the allowlist;
    /// - `appId` must keep a current bounded key (`Unique` or
    ///   `MultipleReferenceToLatest`) of each encryption purpose asked.
    ///
    /// `groupOwners` and `contractOwners` map ids to owner ids; an id missing
    /// from them does not exist. Returns why the request is refused, or nil.
    static func ownershipRefusal(
        for plan: GrantPlan,
        appOwnerId: Data,
        groupOwners: [Data: Data],
        contractOwners: [Data: Data],
        appBoundedKeyPurposes: Set<KeyPurpose>,
        appUnreadableKeyPurposes: Set<KeyPurpose> = []
    ) -> Refusal? {
        if systemContractIds.contains(plan.appId.toBase58String()) {
            return Refusal(.invalid, NSLocalizedString(
                "The request names a Dash Platform system contract as the app.",
                comment: "DashConnect App Connect v2"))
        }
        for grant in plan.auth {
            let binding = grant.binding
            switch binding.kind {
            case .contractGroup:
                guard groupOwners[binding.id] == appOwnerId else {
                    return Refusal(.invalid, NSLocalizedString(
                "The app asks for a key on a contract group it does not own.",
                comment: "DashConnect App Connect v2"))
                }
            case .singleContract, .documentType:
                if binding.kind == .documentType,
                   allowedForeignDocumentTypes.contains("\(binding.id.toBase58String())/\(binding.documentTypeName ?? "")") {
                    continue
                }
                guard !systemContractIds.contains(binding.id.toBase58String()),
                      contractOwners[binding.id] == appOwnerId else {
                    return Refusal(.invalid, NSLocalizedString(
                "The app asks for a key on a contract it does not own.",
                comment: "DashConnect App Connect v2"))
                }
            }
        }
        for grant in plan.encryption where appUnreadableKeyPurposes.contains(grant.keyPurpose) {
            return Refusal(.unsupported, NSLocalizedString(
                "This version of the wallet cannot read how the app's contract keeps its keys. Update the wallet.",
                comment: "DashConnect App Connect v2"))
        }
        for grant in plan.encryption where !appBoundedKeyPurposes.contains(grant.keyPurpose) {
            return Refusal(.invalid, NSLocalizedString(
                "The app's contract keeps no current key bound to it for the encryption it asks for.",
                comment: "DashConnect App Connect v2"))
        }
        return nil
    }

    // MARK: Keys

    /// The DIP-13 leaf of binding `bindingIndex`'s auth key:
    /// `hash256(appEphPub ‖ u8(bindingIndex))`, under the session
    /// authentication sub-feature (`…/6'/0'/identityId'/leaf'`).
    ///
    /// The profile only needs each granted key to be distinct and stable for
    /// one request: the app finds the keys on chain and never derives them.
    /// Folding the index into the leaf gives that with the SDK's
    /// `deriveConnectKey` as it is. Folding it in for binding 0 as well keeps
    /// a v2 key apart from the v1 session key of the same ephemeral key.
    static func authKeyLeaf(appEphemeralPubKey: Data, bindingIndex: Int) -> Data {
        var input = appEphemeralPubKey
        input.append(UInt8(truncatingIfNeeded: bindingIndex))
        return Data(SHA256.hash(data: Data(SHA256.hash(data: input))))
    }

    /// An auth key as it is registered: ECDSA_HASH160, as the v1 session key.
    static func authIdentityPubkey(
        _ grant: AuthGrant,
        keyId: UInt32,
        publicKeyHash160: Data
    ) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: keyId,
            keyType: .ecdsaHash160,
            purpose: .authentication,
            securityLevel: grant.securityLevel,
            pubkeyBytes: publicKeyHash160,
            contractBounds: grant.contractBounds,
            totalBudget: grant.totalBudget,
            expiresAt: grant.expiresAt
        )
    }

    /// An encryption key as it is registered: ECDSA_SECP256K1 (peers need the
    /// point), MEDIUM, bound to the app's contract, with no limits.
    static func encryptionIdentityPubkey(
        _ grant: EncryptionGrant,
        keyId: UInt32,
        publicKey: Data
    ) -> ManagedPlatformWallet.IdentityPubkey {
        ManagedPlatformWallet.IdentityPubkey(
            keyId: keyId,
            keyType: .ecdsaSecp256k1,
            purpose: grant.keyPurpose,
            securityLevel: .medium,
            pubkeyBytes: publicKey,
            contractBounds: .singleContract(id: grant.binding.contractId),
            totalBudget: nil,
            expiresAt: nil
        )
    }

    /// One encryption key this wallet derives, as the data source holds it:
    /// the private key is wiped by whoever owns the array it ends up in.
    typealias DerivedEncryptionKey = (publicKey: Data, privateKey: Data)

    /// DIP "Encryption Keys": every key this wallet can derive for one
    /// encryption binding of `purpose`. The first is always rotation `0'` at
    /// `m/9'/coin'/5'/7'/0'/identityId'/contractId'/purpose'/rotation'`, the
    /// key a login registers when the identity has none for the binding.
    /// Rotations are registered in order, so the later ones are found by
    /// deriving `1'`, `2'`, … and stopping at the first whose key is not on
    /// the identity in any state; that one is wiped, not kept. No more
    /// rotations are derived than the identity has keys of `purpose`.
    ///
    /// On testnet and devnet the key at the path without the rotation level
    /// comes last: wallets built before the DIP registered keys there, and a
    /// current key at that path is still sent. Mainnet never had them, so the
    /// path is not derived there and such a key reads as another wallet's.
    static func derivableEncryptionKeys(
        network: Network,
        purpose: KeyPurpose,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        rotation: (UInt32) throws -> DerivedEncryptionKey,
        legacy: () throws -> DerivedEncryptionKey
    ) throws -> [DerivedEncryptionKey] {
        func isOnIdentity(_ publicKey: Data) -> Bool {
            currentIdentityPublicKeys.contains { $0.purpose == purpose && $0.data == publicKey }
        }
        var keys: [DerivedEncryptionKey] = []
        var kept = false
        defer {
            if !kept { for index in keys.indices { PlatformDashConnectDataSource.zero(&keys[index].privateKey) } }
        }
        keys.append(try rotation(0))
        let maxRotations = max(1, currentIdentityPublicKeys.filter { $0.purpose == purpose }.count)
        var next: UInt32 = 1
        while isOnIdentity(keys[keys.count - 1].publicKey), keys.count < maxRotations {
            var key = try rotation(next)
            guard isOnIdentity(key.publicKey) else {
                PlatformDashConnectDataSource.zero(&key.privateKey)
                break
            }
            keys.append(key)
            next += 1
        }
        if derivesLegacyEncryptionPath(network) {
            keys.append(try legacy())
        }
        kept = true
        return keys
    }

    /// Whether `network` derives encryption keys at the path without the
    /// rotation level as well (DIP "Deployment and Compatibility").
    static func derivesLegacyEncryptionPath(_ network: Network) -> Bool {
        network == .testnet || network == .devnet
    }

    /// What a login does with one granted encryption binding.
    enum EncryptionSlot: Equatable {
        /// Send the identity's current key, which is `derivedIndex` among
        /// the keys `derivableEncryptionKeys` returned; register nothing.
        case send(keyId: UInt32, derivedIndex: Int)
        /// Register rotation `0'` (the first derivable key) and send it.
        case register
        /// Leave the slot out and register nothing.
        case omit
    }

    /// The slot a settled `state` comes to, or nil for one that is not
    /// settled, or a current key that is not among `derivedPublicKeys` as
    /// the fetched keys show it (a read that is behind).
    static func encryptionSlot(
        for state: EncryptionKeyState,
        derivedPublicKeys: [Data],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> EncryptionSlot? {
        switch state {
        case .current(let keyId):
            guard let key = currentIdentityPublicKeys.first(where: { UInt32(bitPattern: $0.keyId) == keyId }),
                  let derivedIndex = derivedPublicKeys.firstIndex(of: key.data) else { return nil }
            return .send(keyId: keyId, derivedIndex: derivedIndex)
        case .absent:
            return .register
        case .notThisWallets:
            return .omit
        case .outOfDate, .absentIfSettled, .notThisWalletsIfSettled, .currentIfSettled:
            return nil
        }
    }

    /// What the identity holds for the app's encryption key of one purpose
    /// (wallet rule 7, DIP "Encryption Keys").
    enum EncryptionKeyState: Equatable {
        /// Its current key is one this wallet derives: send it again.
        case current(keyId: UInt32)
        /// It has no key for the contract and purpose at all: register
        /// rotation `0'`.
        case absent
        /// Its current key is another wallet's, or Platform's current key
        /// for the contract and purpose is disabled, so none is current:
        /// leave the slot out.
        /// Replacing it would be a rotation, which orphans what peers
        /// encrypted to it; that is an explicit user action, never part of a
        /// login.
        case notThisWallets
        /// The fetched keys and Platform's current key disagree: one of the
        /// two reads is behind, and nothing can be said until both agree.
        case outOfDate
        /// `absent`, unless Platform's read is behind a key the store
        /// cannot place: it holds only once a later read says the same.
        case absentIfSettled
        /// `notThisWallets`, unless Platform's read is behind a live key
        /// bound to the app that was registered after the current one: it
        /// holds only once a later read says the same.
        case notThisWalletsIfSettled
        /// `current`, on the same terms.
        case currentIfSettled(keyId: UInt32)

        /// What the state comes to once a later read of Platform's current
        /// key has said the same.
        var settled: EncryptionKeyState {
            switch self {
            case .absentIfSettled: return .absent
            case .notThisWalletsIfSettled: return .notThisWallets
            case .currentIfSettled(let keyId): return .current(keyId: keyId)
            default: return self
            }
        }

        var needsSettling: Bool { settled != self }
    }

    /// How a contract keeps the current key of a purpose it requires bound
    /// keys for. A login sends that key, so only these two take one;
    /// `Multiple` keeps none.
    enum CurrentKeyRule: Equatable {
        /// `Unique` (0): one key ever. The first one registered stays
        /// current after it is disabled, and no other can be added.
        case unique
        /// `MultipleReferenceToLatest` (2): the key registered last is
        /// current, and stays current after it is disabled.
        case latest
    }

    /// What a contract's `requiresIdentity…BoundedKey` value says about the
    /// current key a login sends.
    enum KeyRequirement: Equatable {
        /// It keeps one, under this rule.
        case currentKey(CurrentKeyRule)
        /// None, or `Multiple` (1): it keeps no current key.
        case noCurrentKey
        /// A value this build cannot read.
        case unreadable
    }

    static func keyRequirement(_ value: Any?) -> KeyRequirement {
        guard let value, !(value is NSNull) else { return .noCurrentKey }
        switch exactInteger(value) as UInt8? {
        case 0: return .currentKey(.unique)
        case 1: return .noCurrentKey
        case 2: return .currentKey(.latest)
        default: return .unreadable
        }
    }

    /// A JSON number read only when it is an exact integer that fits, so a
    /// value out of range is unreadable rather than wrapped.
    static func exactInteger<Value: FixedWidthInteger>(_ value: Any?) -> Value? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let whole = number.int64Value
        guard Double(whole) == number.doubleValue else { return nil }
        return Value(exactly: whole)
    }

    /// How a later read of the current keys compares with an earlier one.
    /// Platform never takes a current-key reference away and never gives a
    /// disabled key back, so a read that lacks a key an earlier one named,
    /// or shows it live again, comes from a node that is behind. Key ids say
    /// nothing of order, so two reads that name different keys cannot be
    /// ordered at all.
    enum CurrentKeysRead: Equatable {
        /// It names the same keys.
        case same
        /// It is behind the earlier read for some purpose, and newer for
        /// none.
        case behind
        /// It is newer for some purpose and behind or the same for the rest:
        /// these are the keys to go on with, the earlier read's kept wherever
        /// the later one is behind.
        case newer([KeyPurpose: CurrentContractKey])
        /// The two name different keys for some purpose.
        case conflict
    }

    static func compare(
        earlier: [KeyPurpose: CurrentContractKey],
        later: [KeyPurpose: CurrentContractKey]
    ) -> CurrentKeysRead {
        guard earlier != later else { return .same }
        var merged = earlier
        var isNewer = false
        for purpose in Set(earlier.keys).union(later.keys) {
            let before = earlier[purpose]
            let after = later[purpose]
            guard before != after else { continue }
            if let before {
                guard let after else { continue }
                guard after.keyId == before.keyId && after.data == before.data else { return .conflict }
                if before.isDisabled { continue }
            }
            merged[purpose] = after
            isNewer = true
        }
        return isNewer ? .newer(merged) : .behind
    }

    /// Reads Platform's current keys again, at most `maxRereads` times with
    /// `pause` before each, until an answer is confirmed: one from the first
    /// read is taken as it is unless it waits on a later read or is out of
    /// date; any other needs a later read that names the same keys. A read
    /// that is behind, or fails, is set aside; a newer one is taken and has
    /// to be confirmed in turn; one that conflicts makes the answer out of
    /// date, there being no telling which of the two is behind. An answer
    /// still unconfirmed at the end is out of date, unless none of the later
    /// reads answered: then the last failure is thrown. A failure `isFinal`
    /// calls so is thrown at once.
    static func settle(
        currentKeys: [KeyPurpose: CurrentContractKey],
        maxRereads: Int = 3,
        states: ([KeyPurpose: CurrentContractKey]) throws -> [EncryptionKeyState],
        reread: () async throws -> [KeyPurpose: CurrentContractKey],
        pause: (_ attempt: Int) async -> Void,
        isFinal: (Error) -> Bool = { _ in false }
    ) async throws -> [EncryptionKeyState] {
        var keys = currentKeys
        var result = try states(keys)
        var confirmed = !result.contains(where: { $0.needsSettling || $0 == .outOfDate })
        var rereads = 0
        var readFailure: Error?
        var anyReadAnswered = false
        while !confirmed && rereads < maxRereads {
            rereads += 1
            await pause(rereads)
            // A read that fails says nothing, like one that is behind.
            let later: [KeyPurpose: CurrentContractKey]
            do {
                later = try await reread()
            } catch {
                if isFinal(error) { throw error }
                readFailure = error
                continue
            }
            anyReadAnswered = true
            switch compare(earlier: keys, later: later) {
            case .same:
                result = result.map(\.settled)
                confirmed = !result.contains(.outOfDate)
            case .behind:
                continue
            case .conflict:
                return result.map { _ in .outOfDate }
            case .newer(let merged):
                keys = merged
                result = try states(keys)
            }
        }
        // When no read answered at all, the failure is what there is to say.
        if !confirmed, !anyReadAnswered, let readFailure { throw readFailure }
        return confirmed ? result : result.map { _ in .outOfDate }
    }

    /// The key Platform names as the identity's current one for a contract
    /// and purpose, from a proved `identities.contractKeys` read, as the
    /// contract's `CurrentKeyRule` keeps it. Under `latest` it is the key
    /// registered last, which need not have the highest id. Under either
    /// rule it stays named after it is disabled: Platform does not fall back
    /// to an older one.
    struct CurrentContractKey: Equatable {
        let keyId: UInt32
        let keyType: KeyType?
        let data: Data
        let isDisabled: Bool
    }

    /// The current key `response` names for `identityId` and `purpose`, or
    /// nil when it proves there is none. The response lists every identity
    /// and purpose asked for; one that lacks either, or a key it cannot
    /// read, throws.
    static func currentContractKey(
        from response: [String: Any],
        identityId: String,
        purpose: KeyPurpose
    ) throws -> CurrentContractKey? {
        let name: String
        switch purpose {
        case .encryption: name = "encryption"
        case .decryption: name = "decryption"
        default: throw SDKError.invalidParameter("Only encryption and decryption keys have a current key here")
        }
        guard let purposes = response[identityId] as? [String: Any], let entry = purposes[name] else {
            throw SDKError.serializationError("The contract keys response leaves out the identity's \(name) key")
        }
        if entry is NSNull { return nil }
        guard let key = entry as? [String: Any],
              let keyId: UInt32 = exactInteger(key["id"]),
              let type: UInt8 = exactInteger(key["type"]),
              let hex = key["data"] as? String, let bytes = AppConnect.data(fromHex: hex), !bytes.isEmpty else {
            throw SDKError.serializationError("The contract keys response carries an unreadable \(name) key")
        }
        let disabledAt = key["disabled_at"]
        guard disabledAt == nil || disabledAt is NSNull || (exactInteger(disabledAt) as UInt64?) != nil else {
            throw SDKError.serializationError("The contract keys response carries an unreadable \(name) key")
        }
        return CurrentContractKey(
            keyId: keyId, keyType: KeyType(rawValue: type), data: bytes,
            isDisabled: !(disabledAt == nil || disabledAt is NSNull))
    }

    /// DIP "Encryption Keys", for one granted binding. `currentKey` is the
    /// key Platform names as current under the app's `rule`; it is the
    /// identity's current key only while it is live. `derivedPublicKeys` are
    /// every key this wallet derives for the binding
    /// (`derivableEncryptionKeys`). A live current key among them is sent;
    /// any other live current key is another wallet's and its slot is left
    /// out (rule 1). A disabled current key means a key for the contract and
    /// purpose is on the identity and none is current: the slot is left out
    /// and nothing is registered (rule 2). Only with no current key at all is a
    /// key registered (rule 3). The fetched keys must show the current key
    /// as Platform does.
    ///
    /// Every key bound to the app becomes current when it is registered, so
    /// with no current key at all a live key the store places on the app
    /// means Platform's read is behind, and a key it cannot place is
    /// bound elsewhere once a later read agrees. Beside a current key, a
    /// key the app may hold was registered before it, or after it with
    /// Platform's read behind, so under `latest` the answer waits on a later
    /// read.
    static func encryptionKeyState(
        derivedPublicKeys: [Data],
        purpose: KeyPurpose,
        contractId: Data,
        rule: CurrentKeyRule,
        currentKey: CurrentContractKey?,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding]
    ) -> EncryptionKeyState {
        // The keys of the purpose besides the current one, in any state:
        // placed on the app by the store, or not placed at all.
        var placedInAnyState = false
        var unplaced = false
        for key in currentIdentityPublicKeys where key.purpose == purpose
            && UInt32(bitPattern: key.keyId) != currentKey?.keyId {
            let keyId = UInt32(bitPattern: key.keyId)
            if let stored = bindings.first(where: { $0.keyId == keyId && $0.data == key.data }),
               !stored.hasUnreadableBound {
                if stored.singleContractId == contractId { placedInAnyState = true }
            } else {
                unplaced = true
            }
        }
        guard let currentKey else {
            // Registering a key bound to the app makes it current, so a key
            // the store places on the app with no current key at all, live or
            // disabled, or one of this wallet's keys in any state (they are
            // derived for the app's contract), is a read from before it
            // landed.
            let holdsADerivedKey = currentIdentityPublicKeys.contains(where: {
                $0.purpose == purpose && derivedPublicKeys.contains($0.data)
            })
            if placedInAnyState || holdsADerivedKey { return .outOfDate }
            return unplaced ? .absentIfSettled : .absent
        }
        guard let fetched = currentIdentityPublicKeys.first(where: { UInt32(bitPattern: $0.keyId) == currentKey.keyId }),
              fetched.purpose == purpose, fetched.data == currentKey.data,
              (fetched.disabledAt != nil) == currentKey.isDisabled else {
            return .outOfDate
        }
        // Under `latest`, a key of the app's beside the current one, live or
        // disabled, was registered before it, or after it and Platform's read
        // is behind.
        let mayBeBehind = rule == .latest && (placedInAnyState || unplaced)
        if !currentKey.isDisabled {
            guard fetched.keyType == .ecdsaSecp256k1, currentKey.keyType == .ecdsaSecp256k1,
                  derivedPublicKeys.contains(currentKey.data) else {
                return mayBeBehind ? .notThisWalletsIfSettled : .notThisWallets
            }
            return mayBeBehind ? .currentIfSettled(keyId: currentKey.keyId) : .current(keyId: currentKey.keyId)
        }
        // Rule 2: the identity has a key for the contract and purpose, and
        // none is current. Under `unique` Platform refuses any other; under
        // `latest` a new key would be a rotation, which is the user's
        // explicit action and never part of a login. A later live key with
        // Platform's read behind is the one exception, so under `latest`
        // the answer waits on a later read.
        if rule == .unique { return .notThisWallets }
        return mayBeBehind ? .notThisWalletsIfSettled : .notThisWallets
    }

    /// Wallet rule 8: the live auth keys of this wallet's earlier grants to
    /// the app on the same connection, which the new grant replaces in the
    /// same identity update. None without a connection id. `keeping` holds
    /// the keys the new grant sends again (a retry of the same request).
    static func supersededKeyIds(
        grants: [AppConnectGrant],
        identityId: String,
        appId: String,
        connectionId: String?,
        keeping: Set<UInt32>,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [UInt32] {
        guard let connectionId else { return [] }
        let previous = Set(grants
            .filter { $0.identityId == identityId && $0.appContractId == appId && $0.connectionId == connectionId }
            .flatMap(\.keyIds))
            .subtracting(keeping)
        return currentIdentityPublicKeys
            .filter {
                previous.contains(UInt32(bitPattern: $0.keyId)) && isLiveGrantedKey($0)
            }
            .map { UInt32(bitPattern: $0.keyId) }
            .sorted()
    }

    /// Whether one identity update can turn off all of `keyIds`. A login
    /// that replaces a connection's keys turns them all off in its own
    /// update or is refused: leaving some on would report a replacement
    /// that did not happen. A disconnect takes them in batches.
    static func fitsOneUpdate(disabling keyIds: [UInt32]) -> Bool {
        keyIds.count <= maxKeysDisabledPerUpdate
    }

    /// The contracts and contract groups that v2-shaped keys no record names
    /// are bound to (`unrecordedV2Keys`), other than `appContractId`, the
    /// allowlisted foreign document types and Platform's system contracts
    /// (never a binding's target): a disconnect looks each one up to tell
    /// whether the app's owner owns it.
    static func unrecordedV2KeyBoundIds(
        appContractId: Data,
        keys: [(keyId: UInt32, bound: StoredBound)]
    ) -> (contracts: Set<Data>, groups: Set<Data>) {
        var contracts: Set<Data> = []
        var groups: Set<Data> = []
        for (_, bound) in keys {
            switch bound {
            case .singleContract(let id):
                if id != appContractId, !systemContractIds.contains(id.toBase58String()) { contracts.insert(id) }
            case .documentType(let id, let name):
                if id != appContractId, !systemContractIds.contains(id.toBase58String()),
                   !allowedForeignDocumentTypes.contains("\(id.toBase58String())/\(name)") {
                    contracts.insert(id)
                }
            case .contractGroup(let id):
                groups.insert(id)
            }
        }
        return (contracts, groups)
    }

    /// The ids of the keys in `keys` that belong to the app's v2 grants:
    /// bound to a contract the app's owner owns (`appContractIds`, the app's
    /// own among them), a document type on one, or a contract group that
    /// owner owns (`appGroupIds`). A key bound to a foreign document type v2
    /// allows (DashPay `profile`) is not among them: that bound names no
    /// app, so with no record it may be any app's (`unattributedProfileKeyIds`).
    static func appsV2KeyIds(
        appContractIds: Set<Data>,
        appGroupIds: Set<Data>,
        keys: [(keyId: UInt32, bound: StoredBound)]
    ) -> [UInt32] {
        keys.filter { _, bound in
            switch bound {
            case .singleContract(let id): return appContractIds.contains(id)
            case .documentType(let id, _): return appContractIds.contains(id)
            case .contractGroup(let id): return appGroupIds.contains(id)
            }
        }
        .map(\.keyId)
        .sorted()
    }

    /// The ids of the keys in `keys` bound to a foreign document type v2
    /// allows (DashPay `profile`). Every app can be given such a key and the
    /// bound does not say which one was, so with no record a disconnect
    /// leaves it on; only revoking shared profile access turns these off,
    /// for every app that holds one.
    static func unattributedProfileKeyIds(keys: [(keyId: UInt32, bound: StoredBound)]) -> [UInt32] {
        keys.filter { _, bound in
            guard case .documentType(let id, let name) = bound else { return false }
            return allowedForeignDocumentTypes.contains("\(id.toBase58String())/\(name)")
        }
        .map(\.keyId)
        .sorted()
    }

    /// Whether a v2 key with this expiry may still work at `nowMilliseconds`.
    /// A key that expired stays live on Platform but can no longer sign.
    /// Platform goes by block time, so a device clock up to `clockTolerance`
    /// fast does not count a working key as expired. Every v2 auth key has an
    /// expiry; a key with none is not one, and counts as false here.
    static func isUnexpired(_ expiresAt: Int64?, nowMilliseconds: Int64) -> Bool {
        (expiresAt ?? 0) > nowMilliseconds - Int64(clockTolerance * 1000)
    }

    /// The unattributed profile keys the wallet's store shows as live and
    /// not yet expired: what the Connections screen counts.
    static func storedSharedProfileKeyIds(
        recordedKeyIds: Set<UInt32>,
        bindings: [KeyBinding],
        nowMilliseconds: Int64
    ) -> [UInt32] {
        let unexpired = Set(bindings.filter { isUnexpired($0.expiresAt, nowMilliseconds: nowMilliseconds) }.map(\.keyId))
        return unattributedProfileKeyIds(keys: unrecordedV2Keys(recordedKeyIds: recordedKeyIds, bindings: bindings))
            .filter(unexpired.contains)
    }

    /// The keys revoking shared profile access disables, from a fresh view of
    /// the identity: live, not yet expired, bound to an allowlisted foreign
    /// document type, and named by no confirmed record (`recordedKeyIds`).
    /// `nil` when the view cannot be trusted: a live v2-shaped key no record
    /// names has no readable stored bound, so it may be one of them; or the
    /// store holds one of them that the view lacks, so the node is behind.
    static func sharedProfileKeyIdsToDisable(
        recordedKeyIds: Set<UInt32>,
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        nowMilliseconds: Int64
    ) -> [UInt32]? {
        let hasUnplacedKey = currentIdentityPublicKeys.contains { key in
            let keyId = UInt32(bitPattern: key.keyId)
            return isLiveAppConnectAuthKey(key) && isUnexpired(key.expiresAt, nowMilliseconds: nowMilliseconds)
                && !recordedKeyIds.contains(keyId)
                && !bindings.contains { $0.keyId == keyId && $0.data == key.data && !$0.hasUnreadableBound }
        }
        let fetchedKeyIds = Set(currentIdentityPublicKeys.map { UInt32(bitPattern: $0.keyId) })
        guard !hasUnplacedKey, storedSharedProfileKeyIds(
            recordedKeyIds: recordedKeyIds, bindings: bindings, nowMilliseconds: nowMilliseconds
        ).allSatisfy(fetchedKeyIds.contains) else { return nil }
        let unexpired = Set(currentIdentityPublicKeys
            .filter { isUnexpired($0.expiresAt, nowMilliseconds: nowMilliseconds) }.map { UInt32(bitPattern: $0.keyId) })
        return unattributedProfileKeyIds(keys: unrecordedV2Keys(
            recordedKeyIds: recordedKeyIds, bindings: bindings, currentIdentityPublicKeys: currentIdentityPublicKeys))
            .filter(unexpired.contains)
    }

    /// The live v2-shaped keys on the identity that no grant record of it
    /// names, as a reinstall or a lost record leaves them: HASH160
    /// authentication keys at HIGH or CRITICAL with an expiry (every v2
    /// auth key has one) and a bound the store can read.
    static func unrecordedV2Keys(
        recordedKeyIds: Set<UInt32>,
        bindings: [KeyBinding],
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo]
    ) -> [(keyId: UInt32, bound: StoredBound)] {
        currentIdentityPublicKeys.compactMap { key in
            let keyId = UInt32(bitPattern: key.keyId)
            guard isLiveAppConnectAuthKey(key), key.expiresAt != nil, !recordedKeyIds.contains(keyId),
                  let stored = bindings.first(where: { $0.keyId == keyId && $0.data == key.data }),
                  !stored.hasUnreadableBound, let bound = stored.bound else { return nil }
            return (keyId, bound)
        }
    }

    /// `unrecordedV2Keys` from the store alone, for an identity that is not
    /// the active one: its keys as last loaded.
    static func unrecordedV2Keys(
        recordedKeyIds: Set<UInt32>,
        bindings: [KeyBinding]
    ) -> [(keyId: UInt32, bound: StoredBound)] {
        bindings.compactMap { binding in
            guard binding.isV2AuthKeyShaped, !binding.isDisabled, !binding.hasUnreadableBound,
                  !recordedKeyIds.contains(binding.keyId), let bound = binding.bound else { return nil }
            return (binding.keyId, bound)
        }
    }

    /// The stored form of a bound the wallet registers a key with.
    static func storedBound(of bounds: ManagedPlatformWallet.ContractBounds) -> StoredBound {
        switch bounds {
        case .singleContract(let id): return .singleContract(id)
        case .singleContractDocumentType(let id, let name): return .documentType(contractId: id, name: name)
        case .contractGroup(let id): return .contractGroup(id)
        }
    }

    /// Whether `key`, found on the identity after an update reported a
    /// failure, is the key the update added (`added`): the same id and
    /// payload, live, and everything it was registered with — type,
    /// purpose, level, read-only flag, limits, and the bound as the store
    /// reads it
    /// (`binding`). A key with the same payload but another bound came from
    /// another request that repeated the ephemeral key, and is not taken.
    static func isAddedKey(
        _ key: ManagedIdentity.IdentityPublicKeyInfo,
        added: ManagedPlatformWallet.IdentityPubkey,
        binding: KeyBinding?
    ) -> Bool {
        guard UInt32(bitPattern: key.keyId) == added.keyId, key.data == added.pubkeyBytes, key.disabledAt == nil,
              key.keyType == added.keyType, key.purpose == added.purpose, key.securityLevel == added.securityLevel,
              key.readOnly == added.readOnly,
              key.totalBudget == added.totalBudget,
              key.expiresAt.map({ UInt64(max(0, $0)) }) == added.expiresAt else { return false }
        guard let bounds = added.contractBounds else { return binding == nil || binding?.bound == nil }
        guard let binding, binding.keyId == added.keyId, binding.data == key.data, !binding.hasUnreadableBound else {
            return false
        }
        return binding.bound == storedBound(of: bounds)
    }

    // MARK: A v2 update whose outcome is not known

    /// A key an App Connect v2 update adds, as it adds it: what
    /// `isAddedKey` compares, kept with the grant while the update's outcome
    /// is not known. Nothing in it is secret.
    struct ExpectedKey: Codable, Equatable {
        let keyId: UInt32
        let keyType: KeyType
        let purpose: KeyPurpose
        let securityLevel: SecurityLevel
        let data: Data
        let readOnly: Bool
        let totalBudget: UInt64?
        let expiresAt: UInt64?
        let bound: StoredBound?

        init(_ key: ManagedPlatformWallet.IdentityPubkey) {
            keyId = key.keyId
            keyType = key.keyType
            purpose = key.purpose
            securityLevel = key.securityLevel
            data = key.pubkeyBytes
            readOnly = key.readOnly
            totalBudget = key.totalBudget
            expiresAt = key.expiresAt
            bound = key.contractBounds.map(AppConnect.storedBound(of:))
        }

        /// The key as the update submits it.
        var identityPubkey: ManagedPlatformWallet.IdentityPubkey {
            ManagedPlatformWallet.IdentityPubkey(
                keyId: keyId,
                keyType: keyType,
                purpose: purpose,
                securityLevel: securityLevel,
                pubkeyBytes: data,
                readOnly: readOnly,
                contractBounds: bound.map(AppConnect.contractBounds(of:)),
                totalBudget: totalBudget,
                expiresAt: expiresAt
            )
        }
    }

    /// The bound a key is registered with, from its stored form.
    static func contractBounds(of bound: StoredBound) -> ManagedPlatformWallet.ContractBounds {
        switch bound {
        case .singleContract(let id): return .singleContract(id: id)
        case .documentType(let id, let name): return .singleContractDocumentType(id: id, documentTypeName: name)
        case .contractGroup(let id): return .contractGroup(id: id)
        }
    }

    /// What an update of this wallet to an identity did, by what Platform
    /// never undoes: the keys it added (a key is never removed) and the ids
    /// it disabled (a key is never enabled again). A view that shows all of
    /// it is at that update or past it.
    struct OwnUpdate: Codable, Equatable {
        struct AddedKey: Codable, Equatable {
            let keyId: UInt32
            let data: Data
        }

        var addedKeys: [AddedKey]
        var disabledKeyIds: [UInt32]

        init(added: [ManagedPlatformWallet.IdentityPubkey] = [], disabledKeyIds: [UInt32] = []) {
            addedKeys = added.map { AddedKey(keyId: $0.keyId, data: $0.pubkeyBytes) }
            self.disabledKeyIds = disabledKeyIds
        }

        func isShown(in keys: [ManagedIdentity.IdentityPublicKeyInfo]) -> Bool {
            addedKeys.allSatisfy { added in keys.contains {
                UInt32(bitPattern: $0.keyId) == added.keyId && $0.data == added.data
            } } && showsDisabled(disabledKeyIds, in: keys)
        }
    }

    /// Whether `keys` shows every one of `keyIds`, disabled.
    static func showsDisabled(_ keyIds: [UInt32], in keys: [ManagedIdentity.IdentityPublicKeyInfo]) -> Bool {
        keyIds.allSatisfy { id in keys.contains { UInt32(bitPattern: $0.keyId) == id && $0.disabledAt != nil } }
    }

    /// Notes on every v2 record of `identityId` still waiting for its update
    /// (except `exceptKey`'s, the update's own) that `update` landed after
    /// it was submitted. An earlier note stays: it settles the same way.
    static func noteOwnUpdate(
        _ update: OwnUpdate,
        in grants: inout [AppConnectGrant],
        identityId: String,
        exceptKey: String? = nil
    ) {
        for index in grants.indices
        where grants[index].identityId == identityId && grants[index].key != exceptKey
            && grants[index].pendingUpdate != nil && grants[index].pendingUpdate?.outlivedBy == nil {
            grants[index].pendingUpdate?.outlivedBy = update
        }
    }

    /// What a view of the identity tells of a v2 update whose outcome was
    /// not known.
    enum PendingV2Outcome: Equatable {
        /// Every key it adds is on the identity, live, as it was added.
        case landed
        /// It landed, and what it added is off again: its keys were turned
        /// off since.
        case landedAndOff
        /// It can never land.
        case cannotLand
        /// It may still land, or the view cannot tell.
        case unknown
    }

    /// The outcome of `pending` by what `keys` (a fresh view of the
    /// identity) and `bindings` (the store's bounds) show. No revision is
    /// guessed: the SDK does not say which revision it signed.
    ///
    /// - Every added key there as it was added, or turned off since: it
    ///   landed (`landedAndOff` when every one of them is off).
    /// - A key under one of its ids with other data: Platform refuses an
    ///   update that adds an id the identity has, and never removes a key,
    ///   so it can never land. The same data, live, with
    ///   other limits or another readable bound: the id is another key's.
    /// - Its encryption key (ECDSA_SECP256K1, unique on Platform) under
    ///   another id: it can never land. HASH160 auth keys are not unique,
    ///   so their data elsewhere says nothing.
    /// - An update of this wallet that landed after it was submitted
    ///   (`outlivedBy`) and that `keys` shows: Platform takes an update only
    ///   at one above the identity's revision, and that update took one
    ///   above whatever the wallet's copy held, so `pending` cannot land
    ///   after it. A view that shows that update and none of its ids means
    ///   it never will. No revision is read: what the update did is.
    /// - Every added key is an auth key past its expiry (with
    ///   `clockTolerance`): if it lands, nothing can sign with it. An
    ///   encryption key has no expiry, so this never ends one that adds it.
    ///
    /// A key under an expected id with the expected data and no readable
    /// bound in the store is unknown: the store may not have loaded it yet.
    static func pendingV2Outcome(
        of pending: AppConnectGrant.PendingV2Update,
        currentIdentityPublicKeys keys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding],
        nowMilliseconds: Int64
    ) -> PendingV2Outcome {
        var allLanded = true
        var anyPresent = false
        var offCount = 0
        for expected in pending.addedKeys {
            guard let key = keys.first(where: { UInt32(bitPattern: $0.keyId) == expected.keyId }) else {
                allLanded = false
                continue
            }
            anyPresent = true
            guard key.data == expected.data else { return .cannotLand }
            guard key.disabledAt == nil else {
                offCount += 1
                continue
            }
            let binding = bindings.first { $0.keyId == expected.keyId && $0.data == key.data }
            if isAddedKey(key, added: expected.identityPubkey, binding: binding) { continue }
            allLanded = false
            if expected.bound != nil, binding == nil || binding?.hasUnreadableBound == true { continue }
            return .cannotLand
        }
        if allLanded { return offCount == pending.addedKeys.count ? .landedAndOff : .landed }
        let takenElsewhere = pending.addedKeys.contains { expected in
            expected.keyType == .ecdsaSecp256k1 && keys.contains {
                $0.keyType == .ecdsaSecp256k1 && $0.data == expected.data
                    && UInt32(bitPattern: $0.keyId) != expected.keyId
            }
        }
        if takenElsewhere { return .cannotLand }
        if !anyPresent, pending.outlivedBy?.isShown(in: keys) == true { return .cannotLand }
        let allExpired = pending.addedKeys.allSatisfy { expected in
            expected.purpose == .authentication
                && expected.expiresAt.map { !isUnexpired(Int64(clamping: $0), nowMilliseconds: nowMilliseconds) } == true
        }
        return allExpired ? .cannotLand : .unknown
    }

    /// Settles the v2 records of `identityId` whose update's outcome was not
    /// known, by `pendingV2Outcome`. A landed one becomes a grant like any
    /// other, and the earlier grants its update retired are marked done; one
    /// that landed and is off again is dropped with those marked done; one
    /// that cannot land is dropped; the rest stay as they are.
    static func settlePendingV2Registrations(
        in grants: inout [AppConnectGrant],
        identityId: String,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding],
        nowMilliseconds: Int64
    ) -> (confirmed: [AppConnectGrant], dropped: [AppConnectGrant]) {
        var confirmed: [AppConnectGrant] = []
        var dropped: [AppConnectGrant] = []
        var retired: Set<String> = []
        for grant in grants where grant.identityId == identityId {
            guard let pending = grant.pendingUpdate else { continue }
            switch pendingV2Outcome(
                of: pending, currentIdentityPublicKeys: currentIdentityPublicKeys, bindings: bindings,
                nowMilliseconds: nowMilliseconds
            ) {
            case .landed:
                var settled = grant
                settled.pendingUpdate = nil
                settled.unconfirmedKeyHash160 = nil
                settled.awaitsRecoveredPublish = true
                confirmed.append(settled)
                retired.formUnion(pending.retiredGrantKeys)
            case .landedAndOff:
                dropped.append(grant)
                retired.formUnion(pending.retiredGrantKeys)
            case .cannotLand:
                dropped.append(grant)
            case .unknown:
                break
            }
        }
        let droppedKeys = Set(dropped.map(\.key))
        grants.removeAll { droppedKeys.contains($0.key) }
        for settled in confirmed {
            guard let index = grants.firstIndex(where: { $0.key == settled.key }) else { continue }
            grants[index] = settled
        }
        markKeysDisabled(in: &grants) { retired.contains($0.key) && !$0.isUnconfirmed }
        return (confirmed, dropped)
    }

    /// Whether a newer confirmed grant of the same connection replaced
    /// `grant`: its response is not for the app any more.
    static func isReplaced(_ grant: AppConnectGrant, in grants: [AppConnectGrant]) -> Bool {
        guard let connectionId = grant.connectionId else { return false }
        return grants.contains {
            $0.key != grant.key && $0.identityId == grant.identityId && $0.appContractId == grant.appContractId
                && $0.connectionId == connectionId && !$0.isUnconfirmed && $0.publishedAt > grant.publishedAt
        }
    }

    /// The ids a confirmed record of `identityId` names, and the ids of the
    /// keys a v2 record waiting for its update adds that the store shows
    /// there as added (same data and bound): those are that grant's, not
    /// another app's. An unconfirmed record's id is otherwise not taken: it
    /// may belong to another key by now.
    static func recordedKeyIds(
        of identityId: String,
        grants: [AppConnectGrant],
        bindings: [KeyBinding]
    ) -> Set<UInt32> {
        var ids = Set(grants.filter { $0.identityId == identityId && !$0.isUnconfirmed }.flatMap(\.keyIds))
        for grant in grants where grant.identityId == identityId {
            for expected in grant.pendingUpdate?.addedKeys ?? [] where bindings.contains(where: {
                $0.keyId == expected.keyId && $0.data == expected.data && !$0.hasUnreadableBound
                    && $0.bound == expected.bound
            }) {
                ids.insert(expected.keyId)
            }
        }
        return ids
    }

    /// For a request whose earlier update's outcome is not known, the ids
    /// that update gave the keys this approval derives: each auth key
    /// (`authKeyHash160s`, in request order) and each encryption key it
    /// registers (`registeredEncryptionKeys`, in slot order) under the id it
    /// was added with, so the retry submits the same keys and at most one of
    /// the two updates can land. Nil when they are not the same keys.
    static func keyIdsForRetry(
        of pending: AppConnectGrant.PendingV2Update,
        authKeyHash160s: [Data],
        registeredEncryptionKeys: [Data]
    ) -> (auth: [UInt32], encryption: [UInt32])? {
        func id(of data: Data, purpose: (KeyPurpose) -> Bool) -> UInt32? {
            pending.addedKeys.first { $0.data == data && purpose($0.purpose) }?.keyId
        }
        let auth = authKeyHash160s.compactMap { id(of: $0) { $0 == .authentication } }
        let encryption = registeredEncryptionKeys.compactMap { id(of: $0) { $0 != .authentication } }
        guard auth.count == authKeyHash160s.count, encryption.count == registeredEncryptionKeys.count,
              Set(auth + encryption) == Set(pending.addedKeys.map(\.keyId)),
              auth.count + encryption.count == pending.addedKeys.count else { return nil }
        return (auth, encryption)
    }

    /// A live auth key a login could have granted: HASH160 and never MASTER,
    /// so a damaged record cannot get the identity's own keys disabled.
    static func isLiveGrantedKey(_ key: ManagedIdentity.IdentityPublicKeyInfo) -> Bool {
        key.purpose == .authentication && key.keyType == .ecdsaHash160
            && key.securityLevel != .master && key.disabledAt == nil
    }

    /// Whether a key already on the identity at this binding's derived
    /// payload can be sent again for it: an earlier answer to the same
    /// request (a retry, or an update that landed without confirming). It
    /// still has to be live, bound as the binding asks (`binding`, the
    /// store's record of the key; a key the store does not show, or shows
    /// with another bound, is not sent), carry the level the plan grants,
    /// and limits no wider than the plan's (`clockTolerance` covers a clock
    /// moved back between two tries). The payload alone proves nothing: a
    /// request that repeats another's ephemeral key derives the same one.
    /// A grant recorded for this request, when there is one, must name
    /// exactly the keys sent again; the caller checks that.
    static func canResendAuthKey(
        _ key: ManagedIdentity.IdentityPublicKeyInfo,
        for grant: AuthGrant,
        binding: KeyBinding?,
        now: Date
    ) -> Bool {
        guard let binding, binding.keyId == UInt32(bitPattern: key.keyId), binding.data == key.data,
              !binding.isDisabled, !binding.hasUnreadableBound, binding.bound == grant.storedBound else { return false }
        guard isLiveGrantedKey(key), key.securityLevel == grant.securityLevel,
              key.totalBudget == grant.totalBudget,
              let expiresAt = key.expiresAt, expiresAt > Int64(milliseconds(now)) else { return false }
        return UInt64(expiresAt) <= grant.expiresAt + UInt64(clockTolerance * 1000)
    }

    /// `callback` with `ac=<status>` appended, keeping its query.
    static func callbackURL(_ callback: URL, status: CallbackStatus) -> URL? {
        guard var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "ac", value: status.rawValue)]
        return components.url
    }

    static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded()))
    }
}
