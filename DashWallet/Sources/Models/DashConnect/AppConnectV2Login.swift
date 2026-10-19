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
    /// - `appId` must opt in to bounded keys of each encryption purpose asked.
    ///
    /// `groupOwners` and `contractOwners` map ids to owner ids; an id missing
    /// from them does not exist. Returns why the request is refused, or nil.
    static func ownershipRefusal(
        for plan: GrantPlan,
        appOwnerId: Data,
        groupOwners: [Data: Data],
        contractOwners: [Data: Data],
        appBoundedKeyPurposes: Set<KeyPurpose>
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
        for grant in plan.encryption where !appBoundedKeyPurposes.contains(grant.keyPurpose) {
            return Refusal(.invalid, NSLocalizedString(
                "The app's contract does not take encryption keys bound to it.",
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

    /// What the identity holds for the app's encryption key of one purpose
    /// (wallet rule 7).
    enum EncryptionKeyState: Equatable {
        /// Its current key is the one this wallet derives: send it again.
        case current(keyId: UInt32)
        /// It has none: register the one this wallet derives.
        case absent
        /// Its current key is another wallet's, or the one this wallet
        /// derives was disabled: leave the slot out. Replacing it would be a
        /// rotation, which orphans what peers encrypted to it; that is an
        /// explicit user action, never part of a login.
        case notThisWallets
    }

    /// The key Platform names as the identity's current one for a contract
    /// and purpose, from a proved `identities.contractKeys` read. It is the
    /// key registered last, which need not have the highest id, and it stays
    /// named after it is disabled: Platform does not fall back to an older
    /// one.
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
              let keyId = (key["id"] as? NSNumber)?.uint32Value,
              let type = (key["type"] as? NSNumber)?.uint8Value,
              let hex = key["data"] as? String, let bytes = AppConnect.data(fromHex: hex), !bytes.isEmpty else {
            throw SDKError.serializationError("The contract keys response carries an unreadable \(name) key")
        }
        return CurrentContractKey(
            keyId: keyId, keyType: KeyType(rawValue: type), data: bytes,
            isDisabled: !(key["disabled_at"] is NSNull || key["disabled_at"] == nil))
    }

    /// Rotation 0 only: the key at DIP-13 `7'` for (identity, contract,
    /// purpose). `currentKey` is the key Platform names as current for the
    /// app's `MultipleReferenceToLatest` requirement; this wallet's key is
    /// sent only while it is that one and live. A live key of the purpose
    /// whose bound the wallet's store cannot place counts as the app's, so a
    /// key of unknown origin is never shadowed by a second one.
    static func encryptionKeyState(
        derivedPublicKey: Data,
        purpose: KeyPurpose,
        contractId: Data,
        currentKey: CurrentContractKey?,
        currentIdentityPublicKeys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [KeyBinding]
    ) -> EncryptionKeyState {
        if let currentKey, !currentKey.isDisabled {
            guard currentKey.keyType == .ecdsaSecp256k1, currentKey.data == derivedPublicKey else {
                return .notThisWallets
            }
            return .current(keyId: currentKey.keyId)
        }
        let live = currentIdentityPublicKeys.filter { key in
            guard key.purpose == purpose, key.disabledAt == nil else { return false }
            let keyId = UInt32(bitPattern: key.keyId)
            guard let stored = bindings.first(where: { $0.keyId == keyId && $0.data == key.data }),
                  !stored.hasUnreadableBound else { return true }
            return stored.singleContractId == contractId
        }
        if !live.isEmpty || currentIdentityPublicKeys.contains(where: { $0.data == derivedPublicKey }) {
            return .notThisWallets
        }
        return .absent
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
    /// own among them), a document type on one, a contract group that owner
    /// owns (`appGroupIds`), or a foreign document type v2 allows (DashPay
    /// `profile`). Those are the bindings `ownershipRefusal` lets a request
    /// have. The last can be another app's when its record is lost too; it
    /// is disabled all the same, since a key left on rather than off is what
    /// a disconnect must not do, and that app's next sign-in adds a new one.
    static func appsV2KeyIds(
        appContractIds: Set<Data>,
        appGroupIds: Set<Data>,
        keys: [(keyId: UInt32, bound: StoredBound)]
    ) -> [UInt32] {
        keys.filter { _, bound in
            switch bound {
            case .singleContract(let id): return appContractIds.contains(id)
            case .documentType(let id, let name):
                return appContractIds.contains(id) || allowedForeignDocumentTypes.contains("\(id.toBase58String())/\(name)")
            case .contractGroup(let id): return appGroupIds.contains(id)
            }
        }
        .map(\.keyId)
        .sorted()
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
