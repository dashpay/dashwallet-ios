//
//  SwiftDashSDKRuntimeWalletStore.swift
//  DashWallet
//
//  App-owned Keychain store for the SwiftDashSDK runtime wallet descriptor.
//  The descriptor is the source of truth for restoring the sign-capable
//  wallet representation on app restart without rebuilding it from the
//  plaintext mnemonic.
//

import Foundation
import OSLog
import Security
import SwiftDashSDK

final class SwiftDashSDKRuntimeWalletStore {
    struct Descriptor: Codable, Equatable {
        let walletId: Data
        let serializedWalletBytes: Data
        let network: AppNetwork
        let isImported: Bool
    }

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.runtime-wallet-store")

    private let keychainService = "org.dashfoundation.dash.swift-sdk-runtime"

    func store(_ descriptor: Descriptor, for network: AppNetwork) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(descriptor)

        try delete(for: network)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: descriptorAccount(for: network),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RuntimeWalletStoreError.keychainError(status)
        }

        Self.logger.info("🔐 RTWALLET :: stored runtime wallet descriptor for \(network.rawValue, privacy: .public)")
    }

    func retrieve(for network: AppNetwork) throws -> Descriptor {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: descriptorAccount(for: network),
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw RuntimeWalletStoreError.descriptorNotFound
        }
        guard status == errSecSuccess else {
            throw RuntimeWalletStoreError.keychainError(status)
        }
        guard let data = result as? Data, !data.isEmpty else {
            throw RuntimeWalletStoreError.invalidDescriptor
        }

        do {
            let decoder = PropertyListDecoder()
            return try decoder.decode(Descriptor.self, from: data)
        } catch {
            Self.logger.error("🔐 RTWALLET :: failed to decode descriptor: \(String(describing: error), privacy: .public)")
            throw RuntimeWalletStoreError.invalidDescriptor
        }
    }

    func exists(for network: AppNetwork) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: descriptorAccount(for: network),
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw RuntimeWalletStoreError.keychainError(status)
        }
        return true
    }

    func delete(for network: AppNetwork) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: descriptorAccount(for: network),
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RuntimeWalletStoreError.keychainError(status)
        }

        Self.logger.info("🔐 RTWALLET :: deleted runtime wallet descriptor for \(network.rawValue, privacy: .public)")
    }

    func deleteAllSupportedNetworks() throws {
        try delete(for: .mainnet)
        try delete(for: .testnet)
    }

    private func descriptorAccount(for network: AppNetwork) -> String {
        "wallet.descriptor.\(network.rawValue)"
    }

    enum RuntimeWalletStoreError: LocalizedError {
        case descriptorNotFound
        case invalidDescriptor
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .descriptorNotFound:
                return "Runtime wallet descriptor not found"
            case .invalidDescriptor:
                return "Runtime wallet descriptor is invalid"
            case .keychainError(let status):
                return "Runtime wallet descriptor keychain error: \(status)"
            }
        }
    }
}
