//
//  DWProfileUpdateBridge.swift
//  DashWallet
//
//  Obj-C facade over `DWProfileUpdateCoordinator`. The coordinator
//  uses Swift concurrency + value types that don't bridge to Obj-C;
//  this class wraps the async surface in a completion-based API so
//  `DWDPUpdateProfileModel.m` can call it.
//
//  Mirrors the shape of `DWIdentityRegistrationBridge`.
//
//  Avatar bytes plumbing:
//    - Caller passes a `UIImage` (the cropped avatar from
//      `DWCropAvatarViewController`).
//    - Bridge JPEG-encodes at quality 0.8 — matches what the SDK
//      example app does and keeps the on-chain hash stable for the
//      same cropped image.
//    - Pass `nil` for `avatarImage` when only metadata fields are
//      being updated; the SDK keeps the existing on-chain
//      `avatarHash` / `avatarFingerprint` in that case.
//

import Foundation
import OSLog
import SwiftDashSDK
import UIKit

@objc(DWProfileUpdateBridge)
@MainActor
@objcMembers
public final class DWProfileUpdateBridge: NSObject {

    @objc public static let shared = DWProfileUpdateBridge()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.profile-bridge")

    /// JPEG compression quality used to encode the cropped avatar
    /// before handing the bytes to the SDK. The SDK doesn't care
    /// about format; quality 0.8 keeps the image small while
    /// minimising visible compression.
    private static let avatarJpegQuality: CGFloat = 0.8

    private override init() {
        super.init()
    }

    // MARK: - Obj-C action surface

    /// Write the current identity's DashPay profile via SwiftDashSDK.
    /// Completion fires on the main queue with either the new
    /// display name (echoed from the saved profile) or an `NSError`.
    ///
    /// - `displayName`: trimmed display name, or `nil` / empty to
    ///   clear the field.
    /// - `publicMessage`: trimmed about-me string, or `nil` to clear.
    /// - `avatarURL`: HTTPS URL of the avatar image, or `nil` to
    ///   clear.
    /// - `avatarImage`: the cropped avatar `UIImage`, or `nil` when
    ///   only metadata fields are being updated. JPEG-encoded
    ///   internally at quality 0.8.
    @objc(updateProfileWithDisplayName:publicMessage:avatarURL:avatarImage:completion:)
    public func updateProfile(
        displayName: String?,
        publicMessage: String?,
        avatarURL: String?,
        avatarImage: UIImage?,
        completion: @escaping (NSError?) -> Void
    ) {
        let avatarBytes: Data?
        if let image = avatarImage {
            avatarBytes = image.jpegData(compressionQuality: Self.avatarJpegQuality)
        } else {
            avatarBytes = nil
        }

        Self.logger.info("🪪 PROFILE-BRIDGE :: updateProfile bytes=\(avatarBytes?.count ?? 0, privacy: .public)")

        Task { @MainActor in
            do {
                _ = try await DWProfileUpdateCoordinator.shared.updateProfile(
                    displayName: displayName,
                    publicMessage: publicMessage,
                    avatarUrl: avatarURL,
                    avatarBytes: avatarBytes)
                Self.logger.info("🪪 PROFILE-BRIDGE :: profile update completed")
                completion(nil)
            } catch {
                Self.logger.error("🪪 PROFILE-BRIDGE :: profile update failed: \(String(describing: error), privacy: .public)")
                completion(Self.nsError(from: error))
            }
        }
    }

    // MARK: - Internals

    private static func nsError(from error: Error) -> NSError {
        if let nsError = error as NSError? {
            return nsError
        }
        return NSError(
            domain: "DWProfileUpdateBridge",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
    }
}
