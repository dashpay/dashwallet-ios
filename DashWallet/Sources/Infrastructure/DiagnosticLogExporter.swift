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

enum DiagnosticLogExportError: LocalizedError {
    case noLogsFound
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
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

    private struct ExportContext: Sendable {
        let network: String
        let appVersion: String
        let currentSession: URL?
        let appLogFiles: [URL]
    }

    /// Keep the pre-export ordering explicit and independently testable.
    /// Diagnostics are best-effort at the call site; flushing still runs when
    /// there is no active SDK runtime to snapshot.
    @MainActor
    static func prepareLogsForExport<Context>(
        emitDiagnostics: () async -> Void,
        flush: () -> Void,
        capture: () -> Context
    ) async -> Context {
        await emitDiagnostics()
        flush()
        return capture()
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
        for session in selectedSessions {
            try fm.copyItem(
                at: session.url,
                to: staging.appendingPathComponent(session.url.lastPathComponent, isDirectory: true)
            )
        }
        if !selectedAppLogs.isEmpty {
            let appLogsDir = staging.appendingPathComponent("app-logs", isDirectory: true)
            try fm.createDirectory(at: appLogsDir, withIntermediateDirectories: true)
            for file in selectedAppLogs {
                try fm.copyItem(
                    at: file,
                    to: appLogsDir.appendingPathComponent(file.lastPathComponent)
                )
            }
        }

        let summary = summaryText(
            network: network,
            appVersion: appVersion,
            selectedSessions: selectedSessions,
            currentIsKnown: current != nil,
            totalSessionsOnDevice: onDisk.count,
            appLogCount: selectedAppLogs.count,
            totalAppLogsOnDevice: appLogFiles.count
        )
        try summary.write(
            to: staging.appendingPathComponent("summary.txt"),
            atomically: true,
            encoding: .utf8
        )

        let zipURL = fm.temporaryDirectory.appendingPathComponent("\(archiveName).zip")
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }
        try zipDirectory(at: staging, to: zipURL)
        return zipURL
    }

    /// Main-actor entry point: captures the context that must be read on
    /// the main actor, then runs the blocking staging + zip detached.
    /// Shared by every caller that offers a log export (Tools menu row,
    /// About-screen shake gesture) so the capture rules live in one place.
    @MainActor
    static func exportArchive() async -> Result<URL, Error> {
        // Pin the runtime identity before the awaited snapshot. Main-actor
        // reentrancy can otherwise switch networks while diagnostics are
        // reading SwiftData, producing an archive labelled with a different
        // network than the wallet that was actually inspected.
        let manager = SwiftDashSDKHost.shared.manager
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId
        let capturedNetwork = SwiftDashSDKHost.shared.runningNetwork
            .map { String(describing: $0) } ?? "unknown"
        let context = await prepareLogsForExport(
            emitDiagnostics: {
                // The SDK owns all diagnostic error handling. Missing runtime
                // handles simply mean there is no live state to add; neither
                // condition is allowed to prevent the existing logs export.
                guard let manager, let walletId else {
                    return
                }
                await manager.emitCoreWalletDiagnostics(for: walletId)
            },
            flush: {
                // Make the structured Swift log durable before we capture the
                // session directory and hand file copying to the detached task.
                SDKLogger.flush()
            },
            capture: {
                let bundle = Bundle.main
                let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                return ExportContext(
                    network: capturedNetwork,
                    appVersion: "\(short) (\(build))",
                    // Authoritative record of which directory this run is
                    // writing to; timestamp sorting can be fooled by a clock
                    // rollback or a stale future-dated directory.
                    currentSession: LoggingPreferences.currentSessionDirectory,
                    appLogFiles: DWLogger.sharedInstance().logFiles()
                )
            })

        return await Task.detached(priority: .userInitiated) {
            Result {
                try export(
                    network: context.network,
                    appVersion: context.appVersion,
                    currentSession: context.currentSession,
                    appLogFiles: context.appLogFiles
                )
            }
        }.value
    }

    /// Shared best-effort bridge for the support composer. Support uses the
    /// exact same archive as the Tools and About screens; a failed export is
    /// reported locally and never falls back to a different attachment set.
    @MainActor
    static func exportArchiveForSupport(
        using exporter: () async -> Result<URL, Error> = {
            await DiagnosticLogExporter.exportArchive()
        },
        onFailure: (Error) -> Void = { error in
            DWLogger.log("Support diagnostic archive export failed: \(error.localizedDescription)")
        }
    ) async -> URL? {
        switch await exporter() {
        case .success(let archiveURL):
            return archiveURL
        case .failure(let error):
            onFailure(error)
            return nil
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
