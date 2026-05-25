//
//  DWProfileUpdateCoordinator.swift
//  DashWallet
//
//  App-scoped @MainActor orchestrator for DashPay profile WRITES
//  (display name, public message, avatar URL + optional avatar
//  bytes) via SwiftDashSDK's `createDashPayProfile` /
//  `updateDashPayProfile`.
//
//  Sequence:
//    1. PIN / biometric gate via `DWIdentityAuthorizer` (the same
//       authorizer the registration coordinator uses).
//    2. Resolve the active wallet + model container.
//    3. Look up `PersistentIdentity.identityId` for the wallet at
//       `pinnedIdentityIndex` (mirrors
//       `DWIdentityRegistrationCoordinator.lookupExistingIdentityId`).
//    4. Build a `DashPayProfileUpdate` with the supplied fields.
//       `avatarBytes` (jpeg-encoded `UIImage` from the cropper) is
//       passed through verbatim — SDK computes SHA-256 + dHash
//       internally and only persists the hashes on-chain.
//    5. Decide create-vs-update by inspecting the cached
//       `getDashPayProfile(identityId:)`. If the cache is empty, try
//       `createDashPayProfile`; on the SDK's "profile already exists"
//       error (out-of-sync cache), retry once via `updateDashPayProfile`.
//       Vice versa for the inverse case.
//    6. On success, force-invalidate `DWCurrentUserIdentityInfo` so
//       the next read sees the new fields without waiting for the
//       SDK's next `syncDashPayProfiles` round, and post the
//       canonical `DWDashPayRegistrationStatusUpdated` notification
//       so existing UI observers re-render.
//
//  Concurrency: `@MainActor`-isolated; the FFI calls are `async`
//  hops onto the SDK's tokio runtime. Callers should await from a
//  Task or use `DWProfileUpdateBridge` for completion-based Obj-C
//  integration.
//
//  v1 scope:
//    - Single identity per wallet at `pinnedIdentityIndex = 0`.
//    - Avatar bytes flow: app layer JPEGs the UIImage at quality
//      0.8; the SDK does NOT upload the bytes anywhere — the
//      `avatarUrl` field is still the only on-chain reference. The
//      bytes feed the on-chain integrity hashes only. Hosting the
//      avatar at the URL is the caller's responsibility (Gravatar,
//      public URL, etc.).
//    - No retry on `KeychainSigner`-side cancel — that's an explicit
//      user action and surfaces as `CoordinatorError.authCancelled`.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class DWProfileUpdateCoordinator {

    static let shared = DWProfileUpdateCoordinator()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.profile-coordinator")

    /// Pinned identity index. Aligned with
    /// `DWIdentityRegistrationCoordinator.pinnedIdentityIndex` and
    /// `DWCurrentUserIdentityInfo.pinnedIdentityIndex`.
    private static let pinnedIdentityIndex: UInt32 = 0

    private let authorizer = DWIdentityAuthorizer()

    private init() {}

    // MARK: - Errors

    enum CoordinatorError: LocalizedError {
        case noWallet
        case noModelContainer
        case noIdentity
        case authCancelled
        case authFailed
        case profileWrite(Error)

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready", comment: "DashPay")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "DashPay")
            case .noIdentity:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "DashPay")
            case .profileWrite(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    // MARK: - Public API

    /// Write the profile document for the current identity.
    /// Branches between `createDashPayProfile` and `updateDashPayProfile`
    /// based on the cached profile state.
    ///
    /// - Parameters:
    ///   - displayName: trimmed display name, or `nil` / empty to
    ///     clear the field (sent as empty string to SDK; the SDK
    ///     normalizes nil-or-empty consistently).
    ///   - publicMessage: trimmed about-me string, or `nil` to clear.
    ///   - avatarUrl: HTTPS URL of the avatar image, or `nil` to clear.
    ///   - avatarBytes: raw image bytes (jpeg-encoded) for hash
    ///     computation. Pass `nil` when the user didn't change the
    ///     avatar — the SDK keeps the existing hashes.
    /// - Returns: the freshly-written `DashPayProfile` snapshot.
    @discardableResult
    func updateProfile(
        displayName: String?,
        publicMessage: String?,
        avatarUrl: String?,
        avatarBytes: Data?
    ) async throws -> DashPayProfile {
        Self.logger.info("🪪 PROFILE-COORD :: updateProfile displayName=\(displayName ?? "(nil)", privacy: .public) avatar=\(avatarUrl ?? "(nil)", privacy: .public) bytes=\(avatarBytes?.count ?? 0, privacy: .public)")

        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.error("🪪 PROFILE-COORD :: noWallet — SwiftDashSDKHost.shared.wallet is nil")
            throw CoordinatorError.noWallet
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            Self.logger.error("🪪 PROFILE-COORD :: noModelContainer — SwiftDashSDKHost.shared.modelContainer is nil")
            throw CoordinatorError.noModelContainer
        }
        guard let identityId = lookupIdentityId(
            walletId: wallet.walletId,
            modelContainer: modelContainer)
        else {
            Self.logger.error("🪪 PROFILE-COORD :: noIdentity — no PersistentIdentity row at index \(Self.pinnedIdentityIndex, privacy: .public) for wallet \(wallet.walletId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)…")
            throw CoordinatorError.noIdentity
        }
        Self.logger.info("🪪 PROFILE-COORD :: identity resolved \(identityId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)…, awaiting auth")

        // Yield a beat before triggering the PIN/biometric prompt.
        // The caller's typical flow is:
        //   delegate.editProfileViewController(...) →
        //   updateModel.update(...) (this Task starts) →
        //   controller.dismiss(animated: true)  // .fullScreen modal
        // The dismiss animation runs ~300ms; if we synchronously hit
        // `DSAuthenticationManager.authenticate(...)` immediately, the
        // top view controller is the *dismissing* editor and iOS
        // silently refuses to present the PIN modal — the
        // authentication callback never fires and this coroutine
        // hangs forever. Sleeping ~500ms lets the dismiss animation
        // complete so the parent (HomeViewController / MainMenu)
        // becomes the presenting controller for the PIN prompt.
        //
        // Not load-bearing for correctness in the abstract — a future
        // refactor that hands the editor an explicit completion
        // callback and dismisses only after the bridge resolves would
        // remove the need for this sleep — but the existing
        // fire-and-forget delegate shape (matches the legacy DashSync
        // flow) needs this hop.
        try? await Task.sleep(nanoseconds: 500_000_000)
        Self.logger.info("🪪 PROFILE-COORD :: dismiss-yield complete, requesting auth")

        // PIN / biometric prompt. Throws `.cancelled` on user cancel
        // (translated to our own error so callers don't pull in
        // `DWIdentityAuthorizer`'s symbols).
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw CoordinatorError.authCancelled
        } catch {
            throw CoordinatorError.authFailed
        }
        Self.logger.info("🪪 PROFILE-COORD :: auth granted, proceeding to SDK profile write")

        let signer = KeychainSigner(modelContainer: modelContainer)
        // DIP-15 enforces a minimum length of 1 character on each
        // profile-document string field. Sending an empty string
        // (e.g. the user typed only a display name and left About Me
        // blank) trips a `JsonSchemaError: "" is shorter than 1
        // character` from Platform. Normalise empty → nil so the
        // SDK omits the field entirely. v1 doesn't support clearing
        // a previously-set field (DIP-15 has no explicit "delete"
        // signal — once a field is set it stays unless the user
        // overwrites it with a non-empty value).
        let normalizedDisplayName = Self.nilIfEmpty(displayName)
        let normalizedPublicMessage = Self.nilIfEmpty(publicMessage)
        let normalizedAvatarUrl = Self.nilIfEmpty(avatarUrl)
        let update = DashPayProfileUpdate(
            displayName: normalizedDisplayName,
            publicMessage: normalizedPublicMessage,
            avatarUrl: normalizedAvatarUrl,
            avatarBytes: avatarBytes)

        // create vs update is decided from the cached profile state.
        // The cache can be stale (just-registered identity, or one
        // that hasn't synced yet); if we guess wrong, the SDK returns
        // a deterministic error and we flip the verb on the retry.
        let existing = try? wallet.getDashPayProfile(identityId: identityId)
        let preferCreate = (existing == nil)

        let result: DashPayProfile
        do {
            if preferCreate {
                result = try await wallet.createDashPayProfile(
                    identityId: identityId,
                    update: update,
                    signer: signer)
            } else {
                result = try await wallet.updateDashPayProfile(
                    identityId: identityId,
                    update: update,
                    signer: signer)
            }
        } catch let firstError {
            // Flip the verb only when the error string makes it
            // unambiguous that we picked the wrong one. Transport /
            // decoding / network errors are propagated as-is — they
            // would fail the same way with the opposite verb and the
            // resulting "duplicate" / "not found" noise on the fall-
            // back would mask the real failure.
            let errorText = String(describing: firstError).lowercased()
            let wrongVerb = preferCreate
                ? errorText.contains("duplicate unique") || errorText.contains("duplicate $ownerid")
                : errorText.contains("not found") || errorText.contains("document not found")
            if wrongVerb {
                Self.logger.warning("🪪 PROFILE-COORD :: \(preferCreate ? "create" : "update", privacy: .public) failed with wrong-verb signature; retrying with opposite verb")
                do {
                    if preferCreate {
                        result = try await wallet.updateDashPayProfile(
                            identityId: identityId,
                            update: update,
                            signer: signer)
                    } else {
                        result = try await wallet.createDashPayProfile(
                            identityId: identityId,
                            update: update,
                            signer: signer)
                    }
                } catch let secondError {
                    Self.logger.error("🪪 PROFILE-COORD :: retry failed: \(String(describing: secondError), privacy: .public)")
                    throw CoordinatorError.profileWrite(secondError)
                }
            } else {
                Self.logger.error("🪪 PROFILE-COORD :: \(preferCreate ? "create" : "update", privacy: .public) failed: \(String(describing: firstError), privacy: .public)")
                throw CoordinatorError.profileWrite(firstError)
            }
        }

        Self.logger.info("🪪 PROFILE-COORD :: profile write succeeded")

        // Force-invalidate the helper so the next UI read picks up
        // the new fields, then post the canonical notification so
        // existing observers (home-screen avatar, My Profile, etc.)
        // re-render.
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        NotificationCenter.default.post(
            name: Notification.Name("DWDashPayRegistrationStatusUpdatedNotification"),
            object: nil)
        return result
    }

    // MARK: - Internals

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Resolve the current wallet's identity at `pinnedIdentityIndex`
    /// via SwiftData. Returns `nil` when no `PersistentIdentity` row
    /// exists yet (registration hasn't completed).
    private func lookupIdentityId(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> Identifier? {
        let context = modelContainer.mainContext
        let pinnedIndex = Self.pinnedIdentityIndex
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { identity in
                identity.wallet?.walletId == walletId
                    && identity.identityIndex == pinnedIndex
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.identityId
    }
}
