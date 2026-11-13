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

    /// The most a connection's funding limit can be; every key's budget comes
    /// out of it (`AppConnect.keyBudgets`).
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
    /// document types allowlisted above. A contract added later is still
    /// caught as the app by its owner (`systemContractOwnerId`).
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
        "3iNyoNwjCTkb7XS3RHyWUtLx7pgC6AFAEQNNDHzxqngF", // decision proposals (protocol 15)
        "AE6yYq65VdfGCg2MSyV9vV7cWGiFWjbwBuy7THesDh4e", // token market (protocol 15)
    ]
    /// The owner of every system contract. No identity has this id.
    static let systemContractOwnerId = Data(count: 32)
    /// What a contract group with admins is remembered as owned by: its
    /// admins may add their own contracts to it, so no single owner holds
    /// what is bound to it. No identity has this id.
    static let administeredGroupOwnerId = Data(repeating: 0xFF, count: 32)

    // MARK: What an approval grants

    /// One auth key the approval registers, with the limits the wallet
    /// settled on: the app's proposal, clamped.
    struct AuthGrant: Equatable {
        /// The binding's position in the request. It is part of the key's
        /// derivation, so the key does not depend on what else is granted.
        let bindingIndex: Int
        let binding: AppConnectRequest.AuthBinding
        /// Set when the binding asked for a budget, and on every key once the
        /// user's terms are applied (`AppConnect.applying(_:to:now:)`).
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

    /// What an approval gives an app, as the approval sheet and the
    /// connection sheet list it.
    struct GrantedAccess: Equatable {
        struct Key: Equatable {
            let bound: StoredBound
            let isCritical: Bool
            /// `nil` for a key with no spending limit.
            let totalBudget: UInt64?
            /// Milliseconds since the epoch.
            let expiresAt: UInt64
            /// The key's group has administrators who can add contracts to it.
            let isAdministered: Bool
        }

        let keys: [Key]
        /// The response carries an encryption key for the app.
        let receivesMessages: Bool

        init(keys: [Key], receivesMessages: Bool) {
            self.keys = keys
            self.receivesMessages = receivesMessages
        }

        /// The auth keys of `plan`, with their terms. `receivesMessages`: the
        /// response carries an encryption key, which a plan that asks for one
        /// may still leave out.
        init(plan: GrantPlan, receivesMessages: Bool) {
            self.init(
                keys: plan.auth.map {
                    Key(bound: $0.storedBound, isCritical: $0.securityLevel == .critical, totalBudget: $0.totalBudget,
                        expiresAt: $0.expiresAt, isAdministered: plan.administeredGroupIds.contains($0.binding.id))
                },
                receivesMessages: receivesMessages)
        }

        /// What `intents` gave, in their order: the auth keys each one adds,
        /// with the terms it submitted them with, a key two intents name
        /// once. An intent always names a bound and an expiry for an auth
        /// key; one without is not listed.
        init(intents: [ConnectionIntent]) {
            self.init(intents: intents, snapshot: nil)
        }

        /// `init(intents:)` as the keys on Platform give it, when `snapshot`
        /// read them: a key that landed gives the limits Platform holds now,
        /// which an authorized limits update may have raised; a disabled key,
        /// or one whose id another key holds, gives nothing; a key not there
        /// yet gives its submitted terms while its intent may still land.
        /// `unrecorded`: keys on `snapshot` the projection gives the app that
        /// no intent names, with the limits Platform holds;
        /// `administeredGroups`: the groups of those keys that may have
        /// administrators. Message access, with `snapshot`, is what its
        /// encryption keys still give.
        init(
            intents: [ConnectionIntent], snapshot: IdentitySnapshot?, unrecorded: [PlatformKey] = [],
            administeredGroups: Set<Data> = []
        ) {
            var listed = Set<UInt32>()
            self.init(
                keys: intents.flatMap { intent in
                    let mayLand = snapshot.map { AppConnect.status(of: intent, in: $0) == .confirming } ?? true
                    return intent.authKeys.compactMap { key -> Key? in
                        guard let bound = key.bound, let submittedExpiry = key.expiresAt else { return nil }
                        var expiresAt = submittedExpiry
                        var totalBudget = key.totalBudget
                        if let snapshot {
                            switch AppConnect.presence(of: key, in: snapshot) {
                            case .live, .expired:
                                // Its bound not read yet: not known to be access.
                                guard let actual = AppConnect.accessKey(of: key, in: snapshot) else { return nil }
                                totalBudget = actual.totalBudget
                                expiresAt = actual.expiresAt ?? submittedExpiry
                            case .missing:
                                guard mayLand else { return nil }
                            case .disabled, .conflicting:
                                return nil
                            }
                        }
                        guard listed.insert(key.id).inserted else { return nil }
                        return Key(
                            bound: bound, isCritical: key.securityLevel == .critical, totalBudget: totalBudget,
                            expiresAt: expiresAt, isAdministered: intent.isAdministered(bound))
                    }
                } + unrecorded.compactMap { key -> Key? in
                    // The projection lists only keys with an expiry.
                    guard let bound = key.bound, let expiresAt = key.expiresAt, listed.insert(key.id).inserted else {
                        return nil
                    }
                    var isAdministered = false
                    if case .contractGroup(let id) = bound { isAdministered = administeredGroups.contains(id) }
                    return Key(
                        bound: bound, isCritical: key.securityLevel == .critical, totalBudget: key.totalBudget,
                        expiresAt: expiresAt, isAdministered: isAdministered)
                },
                receivesMessages: intents.contains { intent in
                    let hasMessageKey = !intent.sentEncryptionKeyIds.isEmpty || intent.keys.contains { !$0.isAuthentication }
                    guard hasMessageKey else { return false }
                    return snapshot.map { AppConnect.encryptionKeysGiveAccess(intent, in: $0) } ?? true
                })
        }
    }

    /// What approving a v2 request gives the app, as the approval sheet
    /// shows it. The keys are registered with exactly these terms.
    struct GrantPlan: Equatable {
        let appId: Data
        /// `hash160(appEphPub)`: names the request the plan was made for.
        let appEphemeralPubKeyHash: Data
        /// Set from the request, then from what the user chose on the sheet
        /// (`AppConnect.applying(_:to:now:)`).
        var auth: [AuthGrant]
        let encryption: [EncryptionGrant]
        let connectionId: Data?
        let identityHint: Data?
        /// Milliseconds since the epoch.
        let createdAt: UInt64
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

    /// Why a request dated ahead of the network's time is refused.
    static var futureRequestMessage: String {
        NSLocalizedString("This sign-in request is dated ahead of the network's time. Ask the app for a new code.",
                          comment: "DashConnect App Connect v2")
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

    /// The plan for `uri`: every binding granted, the proposals clamped to
    /// the caps. The request's age, whether a key it asks for has already
    /// expired, and the default and longest expiry of a granted key are all
    /// told from `blockTimeMs`, the block time Platform proved, never from
    /// the phone's clock; without a block time it throws
    /// `requestAgeUncheckable`. A wallet may lower a proposal but must never drop
    /// a limit the app asked for, and every key gets an expiry.
    ///
    /// A renewal (`MODE = 1`) is answered as a new login carrying the same
    /// connection id, which supersedes the old keys (the profile's phase-1
    /// renewal); raising the limits of existing keys is not implemented.
    static func grantPlan(for uri: AppConnectUri, blockTimeMs: UInt64?) throws -> GrantPlan {
        let request = uri.request
        switch request.age(blockTimeMs: blockTimeMs) {
        case .fresh: break
        case .stale: throw Refusal(.stale, NSLocalizedString(
                "The sign-in request is more than 10 minutes old.",
                comment: "DashConnect App Connect v2"))
        case .future: throw Refusal(.stale, futureRequestMessage)
        case .uncheckable: throw DashConnectPlatformError.requestAgeUncheckable
        }
        guard let blockTimeMs else { throw DashConnectPlatformError.requestAgeUncheckable }
        let longest = expiry(after: v2LifetimeCap, from: blockTimeMs)
        let byDefault = expiry(after: v2DefaultLifetime, from: blockTimeMs)
        let auth = try request.authBindings.enumerated().map { index, binding -> AuthGrant in
            if let expiresAt = binding.expiresAt, expiresAt <= blockTimeMs {
                throw Refusal(.invalid, NSLocalizedString(
                "The app asks for a key that has already expired.",
                comment: "DashConnect App Connect v2"))
            }
            return AuthGrant(
                bindingIndex: index,
                binding: binding,
                totalBudget: binding.totalBudget.map { min($0, v2BudgetCapCredits) },
                expiresAt: binding.expiresAt.map { min($0, longest) } ?? byDefault
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
            createdAt: request.createdAt
        )
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
        if systemContractIds.contains(plan.appId.toBase58String()) || appOwnerId == systemContractOwnerId {
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

    /// Wallet rule 3 for a document-type binding: the type has to be one its
    /// contract defines, which Platform checks again when the key is added.
    /// `contracts` holds the contracts preflight read; a binding whose
    /// contract is not among them (the allowlisted DashPay `profile`) is not
    /// checked here. A contract whose document types this build cannot read
    /// asks for an update rather than proving the type missing.
    static func documentTypeRefusal(for plan: GrantPlan, contracts: [Data: [String: Any]]) -> Refusal? {
        for grant in plan.auth where grant.binding.kind == .documentType {
            guard let contract = contracts[grant.binding.id] else { continue }
            guard let schemas = contract["documentSchemas"] as? [String: Any] else {
                return Refusal(.unsupported, NSLocalizedString(
                    "This version of the wallet cannot read the document types of the app's contract. Update the wallet.",
                    comment: "DashConnect App Connect v2"))
            }
            guard schemas[grant.binding.documentTypeName ?? ""] != nil else {
                return Refusal(.invalid, NSLocalizedString(
                    "The app asks for a key on a document type its contract does not define.",
                    comment: "DashConnect App Connect v2"))
            }
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
    /// read. Behind a disabled current key the slot is left out: a new key
    /// would be a rotation, and under `unique` Platform refuses one at all.
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

    /// The stored form of a bound the wallet registers a key with.
    static func storedBound(of bounds: ManagedPlatformWallet.ContractBounds) -> StoredBound {
        switch bounds {
        case .singleContract(let id): return .singleContract(id)
        case .singleContractDocumentType(let id, let name): return .documentType(contractId: id, name: name)
        case .contractGroup(let id): return .contractGroup(id)
        }
    }

    /// `callback` with `ac=<status>` appended, keeping its query.
    static func callbackURL(_ callback: URL, status: CallbackStatus) -> URL? {
        guard var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "ac", value: status.rawValue)]
        return components.url
    }

    /// `lifetime` after the block time `blockTimeMs`, in milliseconds; the
    /// largest time there is when the sum does not fit.
    static func expiry(after lifetime: TimeInterval, from blockTimeMs: UInt64) -> UInt64 {
        let (sum, overflow) = blockTimeMs.addingReportingOverflow(UInt64(lifetime * 1000))
        return overflow ? .max : sum
    }

    static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded()))
    }
}
