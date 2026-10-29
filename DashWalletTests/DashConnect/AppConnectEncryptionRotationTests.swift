import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

/// DIP "Encryption Keys": which encryption key a login sends or registers
/// for a granted binding, with the `rotation'` level and, on testnet and
/// devnet, the earlier path without it (`derivableEncryptionKeys`,
/// `encryptionKeyState`, `encryptionSlot`).
final class AppConnectEncryptionRotationTests: XCTestCase {
    private static let appId = Data(repeating: 0xA1, count: 32)

    // MARK: - A stand-in deriver

    /// Distinct points per rotation and for the earlier path, with private
    /// keys that tell them apart.
    private static func rotationPoint(_ rotation: UInt32) -> Data {
        Data([0x02] + [UInt8](repeating: UInt8(rotation + 1), count: 32))
    }

    private static let legacyPoint = Data([0x03] + [UInt8](repeating: 0xEE, count: 32))

    private static func rotationPrivateKey(_ rotation: UInt32) -> Data {
        Data(repeating: UInt8(rotation + 1), count: 32)
    }

    private static let legacyPrivateKey = Data(repeating: 0xEE, count: 32)

    private final class Deriver {
        private(set) var rotations: [UInt32] = []
        private(set) var legacyCalls = 0

        func rotation(_ rotation: UInt32) -> AppConnect.DerivedEncryptionKey {
            rotations.append(rotation)
            return (AppConnectEncryptionRotationTests.rotationPoint(rotation),
                    AppConnectEncryptionRotationTests.rotationPrivateKey(rotation))
        }

        func legacy() -> AppConnect.DerivedEncryptionKey {
            legacyCalls += 1
            return (AppConnectEncryptionRotationTests.legacyPoint, AppConnectEncryptionRotationTests.legacyPrivateKey)
        }
    }

    private static func encryptionKey(
        _ keyId: UInt32, data: Data, purpose: KeyPurpose = .encryption, disabled: Bool = false
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        ManagedIdentity.IdentityPublicKeyInfo(
            keyId: Int32(bitPattern: keyId), purpose: purpose, securityLevel: .medium, keyType: .ecdsaSecp256k1,
            readOnly: false, disabledAt: disabled ? 1 : nil, data: data, totalBudget: nil, expiresAt: nil)
    }

    private static func binding(_ key: ManagedIdentity.IdentityPublicKeyInfo) -> AppConnect.KeyBinding {
        .init(keyId: UInt32(bitPattern: key.keyId), data: key.data, singleContractId: appId)
    }

    private static func current(_ key: ManagedIdentity.IdentityPublicKeyInfo) -> AppConnect.CurrentContractKey {
        AppConnect.CurrentContractKey(
            keyId: UInt32(bitPattern: key.keyId), keyType: .ecdsaSecp256k1, data: key.data,
            isDisabled: key.disabledAt != nil)
    }

    private struct Login {
        let derived: [AppConnect.DerivedEncryptionKey]
        let state: AppConnect.EncryptionKeyState
        /// The slot once a later read of Platform's current key agrees.
        let slot: AppConnect.EncryptionSlot?

        /// The private key the slot carries, registered or sent.
        var sentPrivateKey: Data? {
            switch slot {
            case .send(_, let derivedIndex): return derived[derivedIndex].privateKey
            case .register: return derived[0].privateKey
            case .omit, nil: return nil
            }
        }
    }

    /// One binding's login against `keys`, as the data source runs it.
    private func login(
        network: Network = .testnet,
        rule: AppConnect.CurrentKeyRule = .latest,
        keys: [ManagedIdentity.IdentityPublicKeyInfo],
        current: AppConnect.CurrentContractKey?,
        bindings: [AppConnect.KeyBinding]? = nil,
        deriver: Deriver = Deriver()
    ) throws -> Login {
        let derived = try AppConnect.derivableEncryptionKeys(
            network: network, purpose: .encryption, currentIdentityPublicKeys: keys,
            rotation: deriver.rotation, legacy: deriver.legacy)
        let state = AppConnect.encryptionKeyState(
            derivedPublicKeys: derived.map(\.publicKey),
            purpose: .encryption,
            contractId: Self.appId,
            rule: rule,
            currentKey: current,
            currentIdentityPublicKeys: keys,
            bindings: bindings ?? keys.map(Self.binding))
        let slot = AppConnect.encryptionSlot(
            for: state.settled, derivedPublicKeys: derived.map(\.publicKey), currentIdentityPublicKeys: keys)
        return Login(derived: derived, state: state, slot: slot)
    }

    // MARK: - Rule 1: a current key

    func testACurrentKeyAtRotationZeroIsSentAndNothingIsRegistered() throws {
        let mine = Self.encryptionKey(5, data: Self.rotationPoint(0))
        for network: Network in [.mainnet, .testnet] {
            let result = try login(network: network, keys: [mine], current: Self.current(mine))
            XCTAssertEqual(result.state, .current(keyId: 5), "\(network)")
            XCTAssertEqual(result.slot, .send(keyId: 5, derivedIndex: 0), "\(network)")
            XCTAssertEqual(result.sentPrivateKey, Self.rotationPrivateKey(0), "\(network)")
        }
    }

    func testACurrentKeyAtRotationOneIsSentBehindADisabledRotationZero() throws {
        let rotationZero = Self.encryptionKey(5, data: Self.rotationPoint(0), disabled: true)
        let rotationOne = Self.encryptionKey(6, data: Self.rotationPoint(1))
        let deriver = Deriver()
        let result = try login(
            network: .mainnet, keys: [rotationZero, rotationOne], current: Self.current(rotationOne), deriver: deriver)
        XCTAssertEqual(deriver.rotations, [0, 1], "two keys on the identity hold at most two rotations")
        XCTAssertEqual(result.derived.map(\.publicKey), [Self.rotationPoint(0), Self.rotationPoint(1)])
        // Rotation 0' beside it may be a later key with Platform's read
        // behind, so the state waits on a later read; once it agrees:
        XCTAssertEqual(result.state, .currentIfSettled(keyId: 6))
        XCTAssertEqual(result.slot, .send(keyId: 6, derivedIndex: 1))
        XCTAssertEqual(result.sentPrivateKey, Self.rotationPrivateKey(1))
    }

    func testAKeyAtTheEarlierPathIsSentOnTestnetAndDevnet() throws {
        let legacy = Self.encryptionKey(5, data: Self.legacyPoint)
        for network: Network in [.testnet, .devnet] {
            let deriver = Deriver()
            let result = try login(network: network, keys: [legacy], current: Self.current(legacy), deriver: deriver)
            XCTAssertEqual(deriver.legacyCalls, 1)
            XCTAssertEqual(result.derived.map(\.publicKey), [Self.rotationPoint(0), Self.legacyPoint])
            XCTAssertEqual(result.state, .current(keyId: 5), "\(network)")
            XCTAssertEqual(result.slot, .send(keyId: 5, derivedIndex: 1), "\(network)")
            XCTAssertEqual(result.sentPrivateKey, Self.legacyPrivateKey, "\(network)")
        }
    }

    /// Mainnet never had keys at the earlier path: the wallet does not derive
    /// it there, so such a key reads as another wallet's and is left out.
    func testTheEarlierPathIsNotDerivedOnMainnet() throws {
        let legacy = Self.encryptionKey(5, data: Self.legacyPoint)
        let deriver = Deriver()
        let result = try login(network: .mainnet, keys: [legacy], current: Self.current(legacy), deriver: deriver)
        XCTAssertEqual(deriver.legacyCalls, 0)
        XCTAssertEqual(result.derived.map(\.publicKey), [Self.rotationPoint(0)])
        XCTAssertEqual(result.state, .notThisWallets)
        XCTAssertEqual(result.slot, .omit)
        XCTAssertNil(result.sentPrivateKey)
        XCTAssertFalse(AppConnect.derivesLegacyEncryptionPath(.mainnet))
        XCTAssertFalse(AppConnect.derivesLegacyEncryptionPath(.regtest))
    }

    func testACurrentKeyThisWalletCannotDeriveIsLeftOut() throws {
        let theirs = Self.encryptionKey(5, data: Data([0x02] + [UInt8](repeating: 0x77, count: 32)))
        for rule: AppConnect.CurrentKeyRule in [.latest, .unique] {
            let result = try login(rule: rule, keys: [theirs], current: Self.current(theirs))
            XCTAssertEqual(result.state, .notThisWallets, "\(rule)")
            XCTAssertEqual(result.slot, .omit, "\(rule)")
        }
    }

    /// Rotations are registered in order: a gap ends the search, so a key
    /// past it is not this wallet's to send.
    func testTheRotationSearchStopsAtTheFirstRotationNotOnTheIdentity() throws {
        let rotationZero = Self.encryptionKey(5, data: Self.rotationPoint(0), disabled: true)
        let rotationTwo = Self.encryptionKey(6, data: Self.rotationPoint(2))
        let deriver = Deriver()
        let result = try login(
            network: .mainnet, keys: [rotationZero, rotationTwo], current: Self.current(rotationTwo), deriver: deriver)
        XCTAssertEqual(deriver.rotations, [0, 1])
        XCTAssertEqual(result.state, .notThisWalletsIfSettled)
        XCTAssertEqual(result.slot, .omit)
        // The first rotation not on the identity is derived, then dropped.
        let elsewhere = Self.encryptionKey(4, data: Data([0x02] + [UInt8](repeating: 0x42, count: 32)))
        let past = Deriver()
        let found = try AppConnect.derivableEncryptionKeys(
            network: .mainnet, purpose: .encryption,
            currentIdentityPublicKeys: [
                elsewhere, Self.encryptionKey(5, data: Self.rotationPoint(0)), Self.encryptionKey(6, data: Self.rotationPoint(1)),
            ],
            rotation: past.rotation, legacy: past.legacy)
        XCTAssertEqual(past.rotations, [0, 1, 2])
        XCTAssertEqual(found.map(\.publicKey), [Self.rotationPoint(0), Self.rotationPoint(1)])
    }

    /// Keys of the other purpose at the same points are not this binding's.
    func testKeysOfTheOtherPurposeDoNotCount() throws {
        let unrelated = [
            Self.encryptionKey(1, data: Data([0x02] + [UInt8](repeating: 0x42, count: 32))),
            Self.encryptionKey(2, data: Data([0x02] + [UInt8](repeating: 0x43, count: 32))),
        ]
        let decryption = [
            Self.encryptionKey(3, data: Self.rotationPoint(0), purpose: .decryption),
            Self.encryptionKey(4, data: Self.rotationPoint(1), purpose: .decryption),
        ]
        let deriver = Deriver()
        _ = try AppConnect.derivableEncryptionKeys(
            network: .mainnet, purpose: .encryption, currentIdentityPublicKeys: unrelated + decryption,
            rotation: deriver.rotation, legacy: deriver.legacy)
        XCTAssertEqual(deriver.rotations, [0])
        // With no current key, a decryption key at the derived point is not
        // this binding's key arriving ahead of Platform's read.
        let result = try login(
            network: .mainnet, keys: [decryption[0]], current: nil,
            bindings: [.init(keyId: 3, data: Self.rotationPoint(0), singleContractId: Self.appId)])
        XCTAssertEqual(result.state, .absent)
        XCTAssertEqual(result.slot, .register)
    }

    // MARK: - Rule 2: keys for the binding, none live

    /// The bug this replaces: a disabled current key of another wallet's
    /// read as absent under `latest`, and the login registered a new key.
    func testOnlyADisabledForeignKeyLeavesTheSlotOutAndRegistersNothing() throws {
        let theirs = Self.encryptionKey(9, data: Data([0x02] + [UInt8](repeating: 0x77, count: 32)), disabled: true)
        for rule: AppConnect.CurrentKeyRule in [.latest, .unique] {
            let result = try login(rule: rule, keys: [theirs], current: Self.current(theirs))
            XCTAssertEqual(result.state, .notThisWallets, "\(rule)")
            XCTAssertEqual(result.slot, .omit, "\(rule)")
            XCTAssertNil(result.sentPrivateKey)
        }
    }

    /// This wallet's own disabled key is not sent (it is not current) and
    /// not replaced (that would be a rotation).
    func testADisabledKeyOfThisWalletsIsNeitherSentNorReplaced() throws {
        let mine = Self.encryptionKey(5, data: Self.rotationPoint(0), disabled: true)
        let result = try login(keys: [mine], current: Self.current(mine))
        XCTAssertEqual(result.slot, .omit)
    }

    // MARK: - Rule 3: nothing for the binding

    func testWithNothingOnTheIdentityRotationZeroAtTheNewPathIsRegistered() throws {
        for network: Network in [.mainnet, .testnet] {
            let deriver = Deriver()
            let result = try login(network: network, keys: [], current: nil, deriver: deriver)
            XCTAssertEqual(deriver.rotations, [0])
            XCTAssertEqual(result.state, .absent, "\(network)")
            XCTAssertEqual(result.slot, .register, "\(network)")
            XCTAssertEqual(result.derived[0].publicKey, Self.rotationPoint(0), "never the earlier path")
            XCTAssertEqual(result.sentPrivateKey, Self.rotationPrivateKey(0))
        }
    }

    // MARK: - Slots that are not settled

    func testAStateThatIsNotSettledHasNoSlot() {
        for state: AppConnect.EncryptionKeyState in [
            .outOfDate, .absentIfSettled, .notThisWalletsIfSettled, .currentIfSettled(keyId: 5),
        ] {
            XCTAssertNil(AppConnect.encryptionSlot(for: state, derivedPublicKeys: [], currentIdentityPublicKeys: []))
        }
        // A current key the fetched keys do not show as a derived one.
        XCTAssertNil(AppConnect.encryptionSlot(
            for: .current(keyId: 5), derivedPublicKeys: [Self.rotationPoint(0)],
            currentIdentityPublicKeys: [Self.encryptionKey(5, data: Self.legacyPoint)]))
    }

    // MARK: - DIP "Key Derivation Vectors", through the wallet's call path

    /// In-memory `WalletStorage`, so the resolver never touches the Keychain.
    private final class InMemoryWalletStorage: WalletStorage {
        private var mnemonics: [Data: Data] = [:]

        override func storeMnemonic(_ mnemonic: String, for walletId: Data) throws {
            mnemonics[walletId] = Data(mnemonic.utf8)
        }

        override func retrieveMnemonicUTF8Bytes(for walletId: Data) throws -> Data {
            guard let data = mnemonics[walletId], !data.isEmpty else { throw WalletStorageError.mnemonicNotFound }
            return data
        }

        override func deleteMnemonic(for walletId: Data) throws {
            mnemonics[walletId] = nil
        }

        override func mnemonicAvailability(for walletId: Data) -> MnemonicAvailability {
            mnemonics[walletId] != nil ? .present : .absent
        }
    }

    @MainActor
    func testTheWalletDerivesTheDIPVectors() throws {
        let storage = InMemoryWalletStorage()
        let walletId = Data(repeating: 0x07, count: 32)
        try storage.storeMnemonic(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            for: walletId)
        // The derive goes through the resolver only, never the wallet handle.
        let wallet = ManagedPlatformWallet(handle: 0, walletId: walletId)

        func derive(
            identityId: Data, contractId: Data, purpose: AppConnectRequest.EncryptionPurpose,
            onIdentity: [String]
        ) throws -> [String] {
            let keyPurpose: KeyPurpose = purpose == .encryption ? .encryption : .decryption
            let keys = try onIdentity.enumerated().map { index, hex in
                Self.encryptionKey(UInt32(index + 1), data: try XCTUnwrap(Data(hex: hex)), purpose: keyPurpose)
            }
            let grant = AppConnect.EncryptionGrant(
                bindingIndex: 0, binding: .init(contractId: contractId, purpose: purpose))
            return try PlatformDashConnectDataSource.derivableEncryptionKeys(
                for: grant, wallet: wallet, identityId: identityId, network: .mainnet,
                currentIdentityPublicKeys: keys, storage: storage
            ).map { $0.publicKey.toHexString() }
        }

        // `m/9'/5'/5'/7'/0'/0x35…'/0x6b…'/1'/{0',1'}`
        let rotationZero = "031a882c119e2b1f8e0349b444d877afa2599efeef49a26930fd25518cb6e9d57a"
        let rotationOne = "03d0f6f0f48d968b9554d8e7fe467d7135bacf29d5c4994ca593bd10ebeed696f6"
        let filled = (Data(repeating: 0x35, count: 32), Data(repeating: 0x6B, count: 32))
        XCTAssertEqual(
            try derive(identityId: filled.0, contractId: filled.1, purpose: .encryption, onIdentity: []),
            [rotationZero], "rotation 0' only, and no earlier path on mainnet")
        XCTAssertEqual(
            try derive(identityId: filled.0, contractId: filled.1, purpose: .encryption, onIdentity: [rotationZero, rotationOne]),
            [rotationZero, rotationOne])

        // `m/9'/5'/5'/7'/0'/asc'/desc'/2'/{0',1'}`
        let ascending = Data((0 ..< 32).map { UInt8($0) })
        let descending = Data((0 ..< 32).map { UInt8(0xFF - $0) })
        let decryptionZero = "020bcde800f41ad1f924477a9502f111445224cc9ab70114ae4e5099ba02bdd034"
        let decryptionOne = "021b97869c21933673076a938337c28848c8bf8094bbe6883e3a4acbf33c639072"
        XCTAssertEqual(
            try derive(identityId: ascending, contractId: descending, purpose: .decryption, onIdentity: [decryptionZero, decryptionOne]),
            [decryptionZero, decryptionOne])
    }
}
