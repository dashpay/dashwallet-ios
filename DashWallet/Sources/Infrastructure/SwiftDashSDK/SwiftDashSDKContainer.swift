//
//  SwiftDashSDKContainer.swift
//  DashWallet
//
//  Shared SwiftData `ModelContainer` owner for dashwallet-ios's use of
//  SwiftDashSDK's `HDWallet` model. We deliberately bypass the SDK's
//  `ModelContainerHelper.createContainer()` because it cannot be made
//  to work in dashwallet-ios's environment, for two compounding reasons:
//
//  1. **It declares a 10-model schema** (`HDWallet` plus 9 platform
//     `Persistent*` types) and the runtime CloudKit-compatibility
//     validation rejects every one of them — the platform models have
//     non-optional attributes without defaults, non-optional
//     relationships, missing relationship inverses, and unique
//     constraints. CloudKit doesn't allow any of those, and SwiftData
//     refuses to load the schema as a result.
//
//  2. **dashwallet-ios has both an App Group entitlement** (Watch app
//     + Today extension data sharing) **and an iCloud entitlement**.
//     SwiftData's default `groupContainer: .automatic` and
//     `cloudKitDatabase: .automatic` auto-detect both, so the SDK
//     helper's `ModelConfiguration` ends up putting the store in the
//     App Group container AND auto-enabling CloudKit sync — which
//     triggers the schema validation in #1.
//
//  The SDK author tested only against `SwiftExampleApp/` which has
//  neither entitlement, so the bug never surfaced upstream. We can't
//  fix the SDK schema from here, but we can build our own minimal
//  `ModelContainer` that:
//
//   - includes ONLY `HDWallet.self` in the schema (the platform
//     `Persistent*` models are unused by dashwallet-ios anyway)
//   - explicitly disables CloudKit (`cloudKitDatabase: .none`) so
//     SwiftData doesn't even attempt CloudKit registration
//   - explicitly disables app-group container (`groupContainer: .none`)
//     so the store lives in the regular app sandbox
//   - uses an explicit store URL under
//     `Library/Application Support/SwiftDashSDKLocal/HDWallet.store` so
//     it cannot collide with anything the SDK helper produces if some
//     other code path manages to call it later
//
//  Threading: the container is created exactly once, on the main thread,
//  at app launch via `warmUp()` from
//  `AppDelegate.didFinishLaunchingWithOptions:`. Subsequent reads from
//  any thread are safe per Apple docs ("`ModelContainer` is thread-safe
//  to read"). Each consumer constructs its own background-queue
//  `ModelContext(container)` against the shared container, which is
//  also documented as supported.
//
//  Hard invariants:
//    1. `warmUp()` MUST be called from the main thread. Enforced by a
//       `precondition`.
//    2. `warmUp()` MUST be called before any background queue reads
//       `modelContainer`. Enforced by AppDelegate ordering.
//    3. After `warmUp()` returns, `modelContainer` is immutable for the
//       app's lifetime — reads from any thread are safe because the
//       `dispatch_async` barriers that schedule background work act as
//       synchronization barriers for the property.
//    4. If creation fails on main, `modelContainer` stays `nil` forever.
//       Consumers must handle the nil case by logging and skipping their
//       SwiftData operations.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKContainer)
public final class SwiftDashSDKContainer: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.container")

    // MARK: - Shared state

    /// The SwiftData container, or `nil` if creation failed (or if
    /// `warmUp()` has not yet been called). Consumers MUST handle the
    /// `nil` case gracefully — log clearly and skip their SwiftData work.
    ///
    /// Reads from background threads are safe AFTER `warmUp()` has
    /// returned and any `dispatch_async` (or equivalent barrier) has
    /// occurred between the warmUp and the read. The expected ordering
    /// from `AppDelegate.didFinishLaunchingWithOptions:` is:
    ///
    ///     [DWSwiftDashSDKContainer warmUp];          // main thread
    ///     [DWSwiftDashSDKKeyMigrator migrateIfNeeded]; // dispatch_async
    ///     [DWSwiftDashSDKSPVCoordinator startIfReady]; // dispatch_async
    ///
    /// `dispatch_async` from main establishes a happens-before edge with
    /// the work it schedules, so the background closures see the
    /// `modelContainer` write performed during `warmUp()`.
    public private(set) static var modelContainer: ModelContainer?

    // MARK: - Public entry point

    /// Create the shared `ModelContainer` synchronously on the main
    /// thread. Idempotent — subsequent calls are no-ops.
    ///
    /// MUST be called from the main thread. Crashes on a `precondition`
    /// failure if called from a background queue, because the entire
    /// purpose of this class is to confine container creation to main.
    ///
    /// Call ONCE from `application:didFinishLaunchingWithOptions:` BEFORE
    /// kicking off any code that touches SwiftData (the seed migrator,
    /// the SPV coordinator, the wallet creator, the wallet wiper, etc).
    @objc(warmUp)
    public static func warmUp() {
        precondition(
            Thread.isMainThread,
            "📦 SDKBOX :: warmUp() must be called from main thread"
        )
        if modelContainer != nil {
            logger.debug("📦 SDKBOX :: warmUp() called again — already initialized")
            return
        }
        do {
            // Minimal HDWallet-only schema — see file header for the
            // full rationale. We deliberately do NOT call
            // `ModelContainerHelper.createContainer()` here.
            let schema = Schema([HDWallet.self])

            // Place the store under Application Support, in our own
            // subdirectory so it can never collide with anything the
            // SDK helper might produce if some other code path manages
            // to call it later.
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
            let storeDirectory = appSupportURL.appendingPathComponent("SwiftDashSDKLocal", isDirectory: true)
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let storeURL = storeDirectory.appendingPathComponent("HDWallet.store")

            // Local-only configuration. Explicit `.none` for both
            // groupContainer and cloudKitDatabase prevents SwiftData
            // from auto-detecting dashwallet-ios's App Group / iCloud
            // entitlements and triggering CloudKit schema validation
            // (which the SDK's models don't satisfy).
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )

            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            logger.info("📦 SDKBOX :: ModelContainer created on main thread (HDWallet-only schema, sandbox store, no CloudKit)")
            logger.info("📦 SDKBOX :: store URL: \(storeURL.path, privacy: .public)")
        } catch {
            let ns = error as NSError
            logger.error("📦 SDKBOX :: ModelContainer init failed: type=\(String(describing: type(of: error)), privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(error.localizedDescription, privacy: .public)")
            // modelContainer stays nil; consumers will hit their nil-handling paths.
        }
    }
}
