//
//  DiagnosticLogExporter.swift
//  DashWallet
//
//  Bundles the app's diagnostic logs into one shareable zip:
//
//   - SwiftDashSDK log sessions — each launch writes one timestamped
//     directory of per-crate `run.log` files under
//     `Library/Logs/SwiftDashSDK/` (installed by
//     `LoggingPreferences.configure()` in `SwiftDashSDKHost`, pruned
//     by the SDK to 20 sessions / 100 MB). The current run's session
//     plus up to two before it are included: after a crash, the run
//     that crashed is usually the session immediately before the
//     current one.
//   - The app's own CocoaLumberjack files (`DWLogger`) under
//     `app-logs/`, newest-first up to a byte cap.
//   - A `summary.txt` of build/device context.
//
//  Nothing is uploaded — callers hand the returned zip to a share
//  sheet or mail composer and the user decides where it goes.
//
//  Session-selection policy and the dependency-free zip are ported
//  from the SwiftDashSDK example app's `LogExporter`
//  (platform #4131, `SwiftExampleApp/Services/LogExporter.swift`);
//  the app-log staging and the two-stream summary are the
//  dashwallet-specific additions.
//

import Foundation
import SwiftDashSDK

enum DiagnosticLogExportError: LocalizedError, Equatable {
    case noLogsFound
    case zipFailed(String)
    /// The lifecycle admission gate is held by a wallet switch, removal,
    /// creation or wipe; the export must not run under one.
    case anotherOperationInProgress
    /// An earlier diagnostic collection has not returned. Distinct from
    /// `anotherOperationInProgress` because no wallet operation is running and
    /// "try again in a moment" would be a lie: the SDK snapshot is behind the
    /// persistence queue, and a second one would only queue behind the first.
    case snapshotStillRunning
    /// The user tapped Cancel on the overlay. Whatever the export produced
    /// afterwards is discarded; callers show nothing for this.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .anotherOperationInProgress:
            return NSLocalizedString(
                "Another wallet operation is in progress. Try again in a moment.",
                comment: "Log export")
        case .snapshotStillRunning:
            return NSLocalizedString(
                "Collecting wallet diagnostics is still running from an earlier attempt. "
                    + "Restart the app if this does not clear.",
                comment: "Log export")
        case .cancelled:
            return NSLocalizedString("Log export cancelled.", comment: "Log export")
        case .noLogsFound:
            return NSLocalizedString(
                "No diagnostic logs were found on this device. Logs are written from the next launch onward.",
                comment: "Log export")
        case .zipFailed(let reason):
            return String.localizedStringWithFormat(
                NSLocalizedString("Could not create the log archive: %@", comment: "Log export"),
                reason)
        }
    }
}

struct DiagnosticLogExporter {
    /// Current run's SDK session + up to two before it.
    static let maxSDKSessions = 3

    /// Older SDK sessions stop being added once the archive's raw
    /// input would pass this. The first selected session (the current
    /// one when known) is always included even if it alone is bigger.
    static let maxSDKSessionBytes: UInt64 = 15 * 1024 * 1024

    /// Byte cap for the `app-logs/` group. `DWLogger` rolls at 5 MB ×
    /// 10 files, so this keeps roughly the two newest rolls without
    /// letting a pathological logs directory balloon the archive.
    static let maxAppLogBytes: UInt64 = 10 * 1024 * 1024

    struct SessionCandidate: Equatable {
        let url: URL
        let bytes: UInt64
    }

    /// Blocking (file I/O + compression) — call off the main actor.
    ///
    /// - Parameters:
    ///   - network: display string for `summary.txt`, captured by the
    ///     caller on the main actor.
    ///   - appVersion: ditto.
    ///   - currentSession: `LoggingPreferences.currentSessionDirectory`,
    ///     captured by the caller on the main actor. `nil` when file
    ///     logging didn't install this launch — the export then falls
    ///     back to newest-on-disk ordering and says so in the summary.
    ///   - appLogFiles: `DWLogger.sharedInstance().logFiles()`,
    ///     captured by the caller (the shared logger is main-thread
    ///     app infrastructure).
    static func export(
        network: String,
        appVersion: String,
        currentSession: URL?,
        appLogFiles: [URL]
    ) throws -> URL {
        let fm = FileManager.default

        // SDK sessions on disk (may be empty — e.g. first launch after
        // the update that enabled file logging crashed early).
        let onDisk: [URL]
        if let root = LoggingPreferences.logsRootDirectory,
           let entries = try? fm.contentsOfDirectory(
               at: root,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            onDisk = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        } else {
            onDisk = []
        }

        let currentOnDisk = currentSession.flatMap { session in
            onDisk.first { $0.lastPathComponent == session.lastPathComponent }
        }
        let current = currentOnDisk.map {
            SessionCandidate(url: $0, bytes: directorySize(of: $0))
        }
        let others = onDisk
            .filter { $0.lastPathComponent != currentOnDisk?.lastPathComponent }
            .map { SessionCandidate(url: $0, bytes: directorySize(of: $0)) }
        let selectedSessions = selectSessions(current: current, others: others)

        let selectedAppLogs = selectAppLogs(appLogFiles)

        guard !selectedSessions.isEmpty || !selectedAppLogs.isEmpty else {
            throw DiagnosticLogExportError.noLogsFound
        }

        // Archive stamp: the newest included SDK session, or the
        // export moment when only app logs exist.
        let stamp: String
        if let first = selectedSessions.first {
            stamp = first.url.lastPathComponent
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
            stamp = formatter.string(from: Date())
        }
        let archiveName = "DashWallet-logs-\(stamp)"
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("LogExport-\(UUID().uuidString)", isDirectory: true)
        let staging = scratch.appendingPathComponent(archiveName, isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        // Best effort per item. The SDK sessions and the app logs are
        // independent evidence: a session directory pruned mid-copy, a name
        // collision or a full disk must not take the other group down with
        // it, and one bad file must not cost the archive. What could not be
        // copied is named in `summary.txt`; only nothing at all is a failure.
        var skipped: [String] = []
        var copiedCount = 0
        for session in selectedSessions {
            do {
                try fm.copyItem(
                    at: session.url,
                    to: staging.appendingPathComponent(session.url.lastPathComponent, isDirectory: true)
                )
                copiedCount += 1
            } catch {
                skipped.append("sdk-session \(session.url.lastPathComponent): \(failureDetail(error))")
            }
        }
        if !selectedAppLogs.isEmpty {
            let appLogsDir = staging.appendingPathComponent("app-logs", isDirectory: true)
            do {
                try fm.createDirectory(at: appLogsDir, withIntermediateDirectories: true)
                for file in selectedAppLogs {
                    do {
                        try fm.copyItem(
                            at: file,
                            to: appLogsDir.appendingPathComponent(file.lastPathComponent)
                        )
                        copiedCount += 1
                    } catch {
                        skipped.append("app-log \(file.lastPathComponent): \(failureDetail(error))")
                    }
                }
            } catch {
                skipped.append("app-logs directory: \(failureDetail(error))")
            }
        }
        guard copiedCount > 0 else {
            // This reason reaches a user-visible alert and there is one entry
            // per failed item, so it is bounded rather than joined whole.
            let head = skipped.prefix(3).joined(separator: "; ")
            let rest = skipped.count > 3 ? "; +\(skipped.count - 3) more" : ""
            throw DiagnosticLogExportError.zipFailed("nothing could be copied (\(head)\(rest))")
        }

        var summary = summaryText(
            network: network,
            appVersion: appVersion,
            selectedSessions: selectedSessions,
            currentIsKnown: current != nil,
            totalSessionsOnDevice: onDisk.count,
            appLogCount: selectedAppLogs.count,
            totalAppLogsOnDevice: appLogFiles.count
        )
        if !skipped.isEmpty {
            summary += "\n\nSkipped (could not be copied):\n"
                + skipped.map { "  - \($0)" }.joined(separator: "\n") + "\n"
        }
        try summary.write(
            to: staging.appendingPathComponent("summary.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Its own directory per export. `archiveName` derives from the SDK
        // session stamp, which is fixed for the process lifetime, so a single
        // path would be rewritten by every export in a launch — including
        // under a live consumer, since the over-25 MB route hands this URL to
        // the share sheet, which reads it lazily and by reference. The
        // directory is also the unit `discardArchive` deletes.
        // Nothing can delete an archive after delivery: the share sheet takes
        // the URL by reference and may read it long after this returns. So the
        // previous ones are swept here instead — the fixed path this replaced
        // was self-cleaning by being overwritten, and without a sweep three
        // support exports leave three archives of up to the mail cap behind,
        // on a device whose free space is one of the things they diagnose.
        let archiveDirectory = fm.temporaryDirectory
            .appendingPathComponent("\(archiveDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        // Claimed BEFORE the sweep and before the directory exists, so a
        // concurrent export's sweep can already see it. Exports really can
        // overlap: an ungated one (About, Tools) takes no lifecycle phase and
        // blocks nothing on screen, so Tools → Export and Contact Support can
        // be in flight together.
        let archiveDirectoryName = archiveDirectory.lastPathComponent
        claimArchiveDirectory(archiveDirectoryName)
        defer { releaseArchiveDirectory(archiveDirectoryName) }
        pruneOldArchiveDirectories()
        try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let zipURL = archiveDirectory.appendingPathComponent("\(archiveName).zip")
        try zipDirectory(at: staging, to: zipURL)
        return zipURL
    }

    /// Names the directory `export` writes its zip into.
    private static let archiveDirectoryPrefix = "LogArchive-"

    /// Archive directories an export is currently writing into. `export` runs
    /// off the main actor on a detached task and two can overlap, so this is
    /// lock-guarded rather than actor-isolated.
    private static let inFlightArchivesLock = NSLock()
    private static var inFlightArchiveNames: Set<String> = []

    private static func claimArchiveDirectory(_ name: String) {
        inFlightArchivesLock.withLock { _ = inFlightArchiveNames.insert(name) }
    }

    private static func releaseArchiveDirectory(_ name: String) {
        inFlightArchivesLock.withLock { _ = inFlightArchiveNames.remove(name) }
    }

    /// Remove the archive directories previous exports left in `tmp`, skipping
    /// any an export is still writing into — deleting one mid-`zipDirectory`
    /// would fail that export, or leave its share sheet holding a URL to a
    /// file that is gone.
    ///
    /// A *delivered* archive is fair game, which is the deliberate part: it is
    /// the only moment anything can collect them, since the share sheet takes
    /// the URL by reference and may read it after this call returns. That
    /// sheet is modal, so it has been dismissed before another export can
    /// start — the cost of being wrong is one unreadable attachment, against a
    /// leak of up to the mail cap per export otherwise.
    ///
    /// Best effort per directory: one that cannot be removed must not stop the
    /// rest being swept.
    private static func pruneOldArchiveDirectories() {
        let fm = FileManager.default
        let live = inFlightArchivesLock.withLock { inFlightArchiveNames }
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries
        where entry.lastPathComponent.hasPrefix(archiveDirectoryPrefix)
            && !live.contains(entry.lastPathComponent) {
            try? fm.removeItem(at: entry)
        }
    }

    /// What a failed copy may say in a file that is mailed to support.
    /// Cocoa's `localizedDescription` embeds the full sandbox path of the item
    /// it failed on, and the SDK redacts store paths out of the very telemetry
    /// this archive carries (`core_store_open_result` is emitted
    /// `redacting: [storeURL.path]`); the host holds the same line. Domain and
    /// code are what a triager acts on anyway.
    private static func failureDetail(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    /// Delete an archive nobody will receive, with the per-export directory
    /// holding it — up to the mail cap per undelivered export, on a device
    /// whose disk pressure is one of the things the export exists to diagnose.
    private static func discardArchive(at url: URL) {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        guard directory.lastPathComponent.hasPrefix(archiveDirectoryPrefix) else {
            // Not one of ours: never take a directory down with the file.
            try? fm.removeItem(at: url)
            return
        }
        try? fm.removeItem(at: directory)
    }

    /// The archive every export screen produces. `includingWalletSnapshot`
    /// adds the SDK's Core-wallet diagnostics (`emitCoreWalletDiagnostics`,
    /// dashpay/platform#4580) to the session log first; the support composer
    /// asks for it, the About shake and the Tools row do not, because that
    /// snapshot holds the SDK's persistence serial queue while it runs and on
    /// a large wallet is the whole cost of the export.
    ///
    /// The snapshot — and ONLY the snapshot — runs behind the app-wide
    /// lifecycle overlay, the same blocking window a wallet switch or creation
    /// uses, in its own `UIWindow`, under the same admission gate: it cannot
    /// start under a switch in flight, and no switch can start under it (a
    /// wipe can: the reset route stays open). `includingWalletSnapshot: false`
    /// takes neither. Those callers copy log files and zip them; they never
    /// touch the SDK's persistence queue, which is the gate's whole
    /// justification, and freezing the app behind a full-screen scrim for a
    /// directory copy — or refusing it because a switch is running, where the
    /// pre-PR export simply ran — would be a cost with nothing bought.
    /// The queue is held only during the snapshot; the card stays up through
    /// flush, capture and zip because the user is waiting for one result and
    /// must not start a second. A refused gate is reported to the caller, not
    /// waited out. Cancel on the card hides the card; the admission is held
    /// until this returns, because the snapshot may still hold the
    /// persistence queue and the pinned manager — a switch must not rebind
    /// under it. The phase carries this export's generation: release and
    /// delivery happen only if the phase is still this export's own — a
    /// cancelled export superseded by a wipe and a newer export must neither
    /// open that export's gate when it finally returns nor deliver an archive
    /// of a wallet the wipe removed.
    @MainActor
    static func exportArchive(includingWalletSnapshot: Bool) async -> Result<URL, Error> {
        let state = WalletLifecycleTransitionState.shared
        var generation: UInt64 = 0
        if includingWalletSnapshot {
            guard !snapshotInFlight else {
                return .failure(DiagnosticLogExportError.snapshotStillRunning)
            }
            WalletLifecycleOverlayPresenter.shared.ensureActive()
            nextExportGeneration += 1
            generation = nextExportGeneration
            guard state.tryBegin(.exportingDiagnostics(dismissed: false, generation: generation)) else {
                return .failure(DiagnosticLogExportError.anotherOperationInProgress)
            }
            snapshotInFlight = true
        }
        defer {
            if includingWalletSnapshot {
                snapshotInFlight = false
                // The gate's timer has nothing left to release.
                dismissedGateTimer?.cancel()
                dismissedGateTimer = nil
            }
            // Only this export's phase — never a `.wiping` admitted through
            // it, and never a successor's export phase. `generation` is 0 for
            // an ungated export, which no phase can carry.
            if case .exportingDiagnostics(_, let owner) = state.phase, owner == generation {
                state.finish()
            }
        }

        // Pin the runtime identity before the awaited snapshot. Main-actor
        // reentrancy can otherwise switch networks while diagnostics are
        // reading SwiftData, producing an archive labelled with a different
        // network than the wallet that was actually inspected.
        let manager = SwiftDashSDKHost.shared.manager
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId
        let capturedNetwork = SwiftDashSDKHost.shared.runningNetwork
            .map { String(describing: $0) } ?? "unknown"
        // The SDK owns all diagnostic error handling. Missing runtime handles
        // simply mean there is no live state to add; neither condition is
        // allowed to prevent the existing logs export.
        if includingWalletSnapshot, let manager, let walletId {
            await manager.emitCoreWalletDiagnostics(for: walletId)
        }
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let appVersion = "\(short) (\(build))"
        // Authoritative record of which directory this run is writing to;
        // timestamp sorting can be fooled by a clock rollback or a stale
        // future-dated directory. A property read, not I/O.
        let currentSession = LoggingPreferences.currentSessionDirectory

        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            // Both flushes block their calling thread on the loggers' queues
            // — deepest right after the snapshot wrote its audit — and the
            // app-log listing enumerates a directory. None of it belongs on
            // the main actor; ordering is kept, since this body runs them
            // before the copy.
            SDKLogger.flush()
            DWLogger.flush()
            let appLogFiles = DWLogger.sharedInstance().logFiles()
            return Result {
                try export(
                    network: capturedNetwork,
                    appVersion: appVersion,
                    currentSession: currentSession,
                    appLogFiles: appLogFiles
                )
            }
        }.value

        // Deliver only if this export still owns an undismissed phase.
        // Cancel dismissed it; a wipe admitted through it moved the phase
        // on, and the wallet the archive describes may be gone by now. An
        // ungated export took no phase and has nothing to lose it to.
        guard includingWalletSnapshot else { return result }
        guard case .exportingDiagnostics(dismissed: false, generation: let owner) = state.phase,
              owner == generation
        else {
            if case .success(let archive) = result { discardArchive(at: archive) }
            return .failure(DiagnosticLogExportError.cancelled)
        }
        return result
    }

    /// Names each export. The phase carries it, so release and delivery can
    /// be scoped to the export that took the phase.
    @MainActor private static var nextExportGeneration: UInt64 = 0

    /// True for the whole life of a snapshot export — through Cancel, and
    /// through the gate's timeout.
    ///
    /// The lifecycle phase deliberately cannot carry this. That phase is
    /// released at `dismissedExportGateTimeout` so the rest of the app can move
    /// again, and a wallet switch started there is safe because it reaches
    /// `manager.shutdown()`, which cancels the diagnostics pass and drains it
    /// before taking the handle. A second SNAPSHOT is the one thing that is
    /// not: it never goes through `shutdown()`, so it would run
    /// `emitCoreWalletDiagnostics` against the same pinned manager and contend
    /// with the first on the SDK's persistence serial queue — on the large
    /// wallet where the first one already failed to finish.
    ///
    /// This is also what makes a tap after the timeout audible: the export is
    /// refused, no card is up, so `shouldStaySilent` lets the alert through —
    /// as `snapshotStillRunning`, which says what actually happened rather
    /// than blaming a wallet operation that is not running.
    ///
    /// Deliberately NOT bounded the way the lifecycle phase is. The phase's
    /// timeout exists to let *other* operations proceed, and they can. A
    /// second snapshot cannot: `emitCoreWalletDiagnostics` runs on the SDK's
    /// persistence serial queue, so releasing this flag would not start a
    /// concurrent pass, it would enqueue one behind the wedged first — more
    /// queued work, no new evidence, and a second admission held. When the
    /// first pass never returns, the queue it is on is stuck, which is a
    /// broken app rather than a busy one, and relaunching is the only real
    /// remedy. The error text says that instead of inviting a retry loop.
    @MainActor private static var snapshotInFlight = false

    /// The gate's release timer, held so it can be cancelled when the export
    /// returns on its own. Unheld, it lingered its full delay poking the
    /// shared phase after everything it guarded was over.
    @MainActor private static var dismissedGateTimer: Task<Void, Never>?

    /// How long a dismissed export may keep the admission gate after its card
    /// is gone. Past this the gate opens even though the export is still
    /// running, because the gate is not what makes that safe: `shutdown()` —
    /// which every wallet switch reaches through the runtime's stop/rebind —
    /// cancels the diagnostics pass and drains its native op before taking the
    /// handle (platform#4580), so a switch started here waits on that drain
    /// instead of racing it. The gate exists to stop the user queueing a
    /// second operation behind a visible one, and after Cancel there is
    /// nothing visible left: a refusal would have no owner on screen to
    /// explain it, and an export wedged behind the persistence queue would
    /// otherwise hold every other operation out until the app is relaunched.
    ///
    /// What the release does NOT permit is a second snapshot — the one
    /// operation that reaches the SDK without passing through `shutdown()`.
    /// `snapshotInFlight` keeps that refused for as long as the first pass
    /// runs, whatever the phase says.
    static let dismissedExportGateTimeout: Duration = .seconds(30)

    /// The overlay card's Cancel. Drops the card now; the export in flight
    /// keeps its admission and, seeing its phase dismissed when it returns,
    /// discards its result as `.cancelled`. That hold is bounded by
    /// `dismissedExportGateTimeout` — a stuck export degrades to a failed
    /// export, not to a gate nothing can open. A no-op unless a card is
    /// showing.
    @MainActor
    static func cancelWaiting() {
        let state = WalletLifecycleTransitionState.shared
        guard case .exportingDiagnostics(dismissed: false, generation: let owner) = state.phase
        else { return }
        state.advance(to: .exportingDiagnostics(dismissed: true, generation: owner))
        dismissedGateTimer?.cancel()
        dismissedGateTimer = Task { @MainActor in
            try? await Task.sleep(for: dismissedExportGateTimeout)
            // Only if this export still owns a dismissed phase: it may have
            // returned and released, or been superseded by a wipe and a
            // successor export, in which case the gate is not ours to open.
            guard case .exportingDiagnostics(dismissed: true, generation: let stillOwner) = state.phase,
                  stillOwner == owner
            else { return }
            DWLogger.log(
                "🚦 LIFECYCLE releasing the gate of dismissed export #\(owner) after \(dismissedExportGateTimeout); the export has not returned")
            state.finish()
        }
    }

    /// Failures the asking screen must stay silent about.
    ///
    /// `.cancelled` is the user's own Cancel. `.anotherOperationInProgress` is
    /// silent only while the operation that refused it is on screen: the
    /// overlay window sits at `.alert + 1`, above the level
    /// `UIAlertController` presents at, so an alert raised now is drawn under
    /// the card — invisible while it is true, and stale by the time the card
    /// drops. The card is the explanation. With no card up (a dismissed export
    /// still holding the gate) the alert is the only explanation there is, and
    /// it shows.
    @MainActor
    static func shouldStaySilent(about error: Error) -> Bool {
        switch error as? DiagnosticLogExportError {
        case .cancelled:
            return true
        case .anotherOperationInProgress, .snapshotStillRunning:
            // Same rule for both, and for the same reason: an alert raised
            // while the overlay window is up at `.alert + 1` is drawn beneath
            // it. Invisible is not the worst of it — an invisible
            // presentation is still a presentation, so UIKit later drops the
            // successful export's mail composer as "already presenting" and
            // the good archive is thrown away with nothing on screen.
            //
            // A second Contact Support tap really can race the first export's
            // card, so this is asked rather than assumed. With no card up (the
            // post-cancel and post-timeout cases) the alert shows, which is
            // the whole point of these two errors having distinct text.
            return WalletLifecycleOverlayPresenter.shared.isPresenting
        default:
            return false
        }
    }

    /// Pure SDK-session selection policy, split out for unit testing.
    ///
    /// The current session (when known) is always first and always
    /// included, no matter how its timestamp sorts against the rest —
    /// it's the authoritative record of this run, not a candidate.
    /// Older sessions then fill the remaining slots newest-first until
    /// either cap is hit. The walk stops at the first session that
    /// would breach the byte cap rather than skipping past it: a gap
    /// in the middle of "the last three runs" would be more confusing
    /// than a shorter archive.
    static func selectSessions(
        current: SessionCandidate?,
        others: [SessionCandidate],
        maxSessions: Int = DiagnosticLogExporter.maxSDKSessions,
        maxTotalBytes: UInt64 = DiagnosticLogExporter.maxSDKSessionBytes
    ) -> [SessionCandidate] {
        var selected: [SessionCandidate] = []
        var totalBytes: UInt64 = 0

        if let current {
            selected.append(current)
            totalBytes = current.bytes
        }

        // Fixed-width UTC stamps: lexicographic == chronological.
        let newestFirst = others.sorted {
            $0.url.lastPathComponent > $1.url.lastPathComponent
        }
        for candidate in newestFirst {
            guard selected.count < maxSessions else { break }
            if !selected.isEmpty && totalBytes + candidate.bytes > maxTotalBytes { break }
            selected.append(candidate)
            totalBytes += candidate.bytes
        }
        return selected
    }

    /// App-log selection: newest-first (by modification date) until
    /// the byte cap. The newest file is always included even if it
    /// alone exceeds the cap — an empty `app-logs/` group would be
    /// worse than a slightly oversized one.
    static func selectAppLogs(
        _ files: [URL],
        maxTotalBytes: UInt64 = DiagnosticLogExporter.maxAppLogBytes
    ) -> [URL] {
        let described: [(url: URL, bytes: UInt64, modified: Date)] = files.map { url in
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (
                url: url,
                bytes: UInt64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast
            )
        }
        var selected: [URL] = []
        var totalBytes: UInt64 = 0
        for file in described.sorted(by: { $0.modified > $1.modified }) {
            if !selected.isEmpty && totalBytes + file.bytes > maxTotalBytes { break }
            selected.append(file.url)
            totalBytes += file.bytes
        }
        return selected
    }

    /// Zip without third-party dependencies: a coordinated read with
    /// `.forUploading` makes the system produce a zip of a directory
    /// in a temporary location that is only valid inside the accessor,
    /// so the copy to `destination` happens in the block.
    private static func zipDirectory(at source: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source,
            options: .forUploading,
            error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError {
            throw DiagnosticLogExportError.zipFailed(coordinatorError.localizedDescription)
        }
        if let copyError {
            throw DiagnosticLogExportError.zipFailed(copyError.localizedDescription)
        }
    }

    private static func directorySize(of directory: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            )
            total += UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private static func summaryText(
        network: String,
        appVersion: String,
        selectedSessions: [SessionCandidate],
        currentIsKnown: Bool,
        totalSessionsOnDevice: Int,
        appLogCount: Int,
        totalAppLogsOnDevice: Int
    ) -> String {
        let iso = ISO8601DateFormatter()
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file

        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: &machine.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #if targetEnvironment(simulator)
        let environment = "simulator"
        #else
        let environment = "device"
        #endif

        var lines: [String] = [
            "Dash Wallet diagnostic log export",
            "Generated: \(iso.string(from: Date()))",
            "",
            "App version: \(appVersion)",
            "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Hardware: \(model) (\(environment))",
            "Network: \(network)",
            "",
            "SwiftDashSDK sessions included (one directory per app launch):",
        ]
        if selectedSessions.isEmpty {
            lines.append("  none on this device (file logging starts on the next launch)")
        }
        for (index, session) in selectedSessions.enumerated() {
            let role: String
            switch (index, currentIsKnown) {
            case (0, true): role = "current session"
            case (0, false):
                role = "newest session on disk (current session unknown — "
                    + "file logging was not active this launch)"
            case (1, _): role = "previous session — after a crash, the crashed run is usually this one"
            default: role = "older session"
            }
            lines.append(
                "  \(session.url.lastPathComponent)  "
                    + "[\(sizeFormatter.string(fromByteCount: Int64(session.bytes)))] — \(role)"
            )
        }
        lines.append("")
        lines.append(
            "Included \(selectedSessions.count) of \(totalSessionsOnDevice) SDK session(s) "
                + "(limit: \(maxSDKSessions) sessions / "
                + "\(sizeFormatter.string(fromByteCount: Int64(maxSDKSessionBytes))) raw) and "
                + "\(appLogCount) of \(totalAppLogsOnDevice) app log file(s) under app-logs/ "
                + "(limit: \(sizeFormatter.string(fromByteCount: Int64(maxAppLogBytes)))).")
        return lines.joined(separator: "\n") + "\n"
    }
}
