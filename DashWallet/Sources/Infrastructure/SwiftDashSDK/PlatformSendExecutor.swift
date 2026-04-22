//
//  PlatformSendExecutor.swift
//  DashWallet
//
//  Thin @MainActor facade over `PlatformAddressSyncCoordinator.transfer(...)`.
//  UI call site stays as `PlatformSendExecutor.shared.transfer(destination:amount:)`
//  while the coordinator owns the SDK handle, mnemonic read, key derivation,
//  and bech32m decoding.
//

import Foundation
import OSLog
import SwiftDashSDK

@MainActor
final class PlatformSendExecutor {
    static let shared = PlatformSendExecutor()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.platform-send-executor")

    private init() {}

    func transfer(destination: String, amount: UInt64) async throws {
        _ = try await PlatformAddressSyncCoordinator.shared.transfer(
            destination: destination,
            amount: amount)
    }
}
