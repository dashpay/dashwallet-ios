import Foundation

/// Local provenance for DashPay payments funded by a Platform or Shielded
/// withdrawal. These are submission records, never Core transaction IDs or
/// proof that a recipient has received funds. The withdrawal SDK does not
/// return a Core transaction ID. Keep this journal separate from its Core
/// payment history.
///
/// `shared` because its three users — the withdrawal coordinator that writes
/// it, the contacts service that reads it, and the wallet wiper that clears
/// it — must agree on one file location; `init(directory:)` is the seam
/// tests use.
///
/// TODO(dashpay-withdrawal-reconcile): nothing moves an entry past
/// `.submitted` or out of `.unconfirmed`. Matching the payout seen on Core to
/// its entry needs the reserved address in the sender's view of the contact's
/// payments, which the SDK does not record for withdrawals.
final class DashPayWithdrawalStore {
    static let shared = DashPayWithdrawalStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DashPayWithdrawals", isDirectory: true))

    static let didChangeNotification = Notification.Name("DWDashPayWithdrawalsDidChange")

    struct Scope: Codable, Equatable {
        let networkRaw: Int
        let walletId: Data
        let ownerIdentityId: Data
    }

    enum Source: String, Codable {
        case platform
        case shielded
    }

    enum Status: String, Codable {
        /// Persisted before invoking the opaque withdrawal SDK call. A crash
        /// can leave this state behind even if submission succeeded.
        case submitting
        /// SDK accepted the withdrawal; the Core payout is still asynchronous.
        case submitted
        /// Submission was attempted but its result could not be established.
        case unconfirmed
    }

    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let scope: Scope
        let contactIdentityId: Data
        let address: String
        let amountDuffs: UInt64
        let amountIsEstimate: Bool
        let source: Source
        let createdAt: Date
        var status: Status
    }

    enum StoreError: LocalizedError {
        case invalidPayment
        case missingEntry

        var errorDescription: String? {
            switch self {
            case .invalidPayment:
                return NSLocalizedString("Unable to save this DashPay payment.", comment: "DashPay: the payment record could not be written, so nothing was sent")
            case .missingEntry:
                return NSLocalizedString("The DashPay payment record is unavailable.", comment: "DashPay: the payment record to update is missing")
            }
        }
    }

    private let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    /// Call after authorization and address reservation, immediately BEFORE
    /// invoking the withdrawal. A failed save must prevent submission. Keep
    /// the captured scope through awaits so a wallet switch cannot relabel it.
    func begin(
        scope: Scope,
        contactIdentityId: Data,
        address: String,
        amountDuffs: UInt64,
        amountIsEstimate: Bool = false,
        source: Source
    ) throws -> Entry {
        guard scope.walletId.count == 32, scope.ownerIdentityId.count == 32,
              contactIdentityId.count == 32, !address.isEmpty, amountDuffs > 0,
              WalletEnvironment.NetworkKind(rawValue: scope.networkRaw) != nil else {
            throw StoreError.invalidPayment
        }
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: scope)
        let entry = Entry(
            id: UUID(), scope: scope, contactIdentityId: contactIdentityId,
            address: address, amountDuffs: amountDuffs,
            amountIsEstimate: amountIsEstimate, source: source,
            createdAt: Date(), status: .submitting)
        entries.append(entry)
        try save(entries, scope: scope)
        return entry
    }

    func update(_ entry: Entry, status: Status) throws {
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: entry.scope)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            throw StoreError.missingEntry
        }
        entries[index].status = status
        try save(entries, scope: entry.scope)
    }

    /// Only remove when the caller knows submission never happened. Unknown
    /// outcomes must remain visible across restarts; they are never retried by
    /// this store or inferred successful from a payment to the same address.
    func remove(_ entry: Entry) throws {
        lock.lock()
        defer { lock.unlock() }
        let entries = try load(scope: entry.scope).filter { $0.id != entry.id }
        try save(entries, scope: entry.scope)
    }

    func entries(scope: Scope, contactIdentityId: Data) throws -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return try load(scope: scope)
            .filter { $0.scope == scope && $0.contactIdentityId == contactIdentityId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// True when a withdrawal to this contact recorded since `date` was never
    /// confirmed as submitted (`.submitting` or `.unconfirmed`).
    func hasUnresolvedEntry(scope: Scope, contactIdentityId: Data, since date: Date) throws -> Bool {
        try entries(scope: scope, contactIdentityId: contactIdentityId)
            .contains { $0.status != .submitted && $0.createdAt >= date }
    }

    /// The wallet's journal files. Throws when the journal can't be read:
    /// only a directory that is genuinely absent reads as empty, because
    /// `fileExists` also answers false when existence can't be determined.
    /// Wallet removal calls this before deleting anything, so a journal it
    /// could not clear afterwards refuses the removal instead.
    func files(ofWallet walletId: Data) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return try walletFiles(walletId)
    }

    func clearForWallet(walletId: Data) throws {
        try clearForWallets(walletIds: [walletId])
    }

    /// All or nothing across every wallet id given — a logical wallet has one
    /// per network: their files move into one staging directory that still
    /// reads as the journal, which is then retired in one rename. A failure
    /// part way leaves every record counted, here or there.
    func clearForWallets(walletIds: [Data]) throws {
        lock.lock()
        defer { lock.unlock() }
        sweepRetired(in: directory)
        sweepRetired(in: directory.deletingLastPathComponent())
        let walletHexes = Set(walletIds.map(Self.hex))
        // Records an earlier, interrupted clear staged first: a live file of
        // the same name was written after it, from its contents, so it is
        // the newer one and replaces it below.
        var files: [URL] = []
        let earlierStagings = try stagingDirectories()
        for staging in earlierStagings {
            files += try FileManager.default.contentsOfDirectory(
                at: staging, includingPropertiesForKeys: nil)
                .filter { Self.walletHex(ofFile: $0).map(walletHexes.contains) == true }
        }
        files += try liveFiles().filter { Self.walletHex(ofFile: $0).map(walletHexes.contains) == true }
        guard !files.isEmpty else { return }
        let staging = directory.appendingPathComponent(
            "\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in files {
            let staged = staging.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.moveItem(at: file, to: staged)
        }
        try retire(staging, in: directory)
        for earlier in earlierStagings {
            // Emptied above unless it also holds other wallets' records.
            if (try? FileManager.default.contentsOfDirectory(atPath: earlier.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: earlier)
            }
        }
        notifyChange()
    }

    /// The same, for the whole journal at once.
    func resetForWipe() throws {
        lock.lock()
        defer { lock.unlock() }
        let parent = directory.deletingLastPathComponent()
        sweepRetired(in: parent)
        do {
            try retire(directory, in: parent)
        } catch CocoaError.fileNoSuchFile {
            // Nothing was ever journaled.
        }
        notifyChange()
    }

    /// Renames `url` out of the journal — the one step that drops its
    /// records — then deletes it. A copy the deletion leaves behind is no
    /// longer read, and the next clear or wipe sweeps it.
    private func retire(_ url: URL, in parent: URL) throws {
        let retired = parent.appendingPathComponent(
            "\(retiredPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: url, to: retired)
        try? FileManager.default.removeItem(at: retired)
    }

    private func sweepRetired(in parent: URL) {
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil)) ?? []
        for leftover in leftovers where leftover.lastPathComponent.hasPrefix(retiredPrefix) {
            try? FileManager.default.removeItem(at: leftover)
        }
    }

    private var retiredPrefix: String { ".\(directory.lastPathComponent)-retired-" }

    private let stagingPrefix = ".clearing-"

    /// The journal's entries; only a directory that is genuinely absent
    /// reads as empty.
    private func directoryEntries() throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    private func liveFiles() throws -> [URL] {
        try directoryEntries().filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    /// Where interrupted clears left records they had not yet retired.
    private func stagingDirectories() throws -> [URL] {
        try directoryEntries().filter { $0.lastPathComponent.hasPrefix(stagingPrefix) }
    }

    private func walletFiles(_ walletId: Data) throws -> [URL] {
        let walletHex = Self.hex(walletId)
        return try liveFiles().filter { Self.walletHex(ofFile: $0) == walletHex }
    }

    /// `<network>_<walletHex>_<ownerHex>.json` → `walletHex`.
    private static func walletHex(ofFile url: URL) -> String? {
        url.lastPathComponent.split(separator: "_").dropFirst().first.map(String.init)
    }

    private func fileURL(scope: Scope) -> URL {
        directory.appendingPathComponent(
            "\(scope.networkRaw)_\(Self.hex(scope.walletId))_\(Self.hex(scope.ownerIdentityId)).json")
    }

    /// The live file, or else the copy a clear that has not finished staged.
    /// A file is staged only by moving it into a fresh staging directory, so
    /// there is at most one staged copy; more than one fails closed, since
    /// which is newer can't be told.
    ///
    /// Anything but a missing file throws: `fileExists` also answers false
    /// when existence can't be determined, and an unreadable journal must
    /// lock contact payments rather than read as empty. Nor is corrupt
    /// history overwritten with an empty one.
    private func load(scope: Scope) throws -> [Entry] {
        if let data = try read(fileURL(scope: scope)) {
            return try JSONDecoder().decode([Entry].self, from: data)
        }
        let name = fileURL(scope: scope).lastPathComponent
        let staged = try stagingDirectories().compactMap { try read($0.appendingPathComponent(name)) }
        guard staged.count <= 1 else { throw CocoaError(.fileReadCorruptFile) }
        return try staged.first.map { try JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    /// Nil only when the file is genuinely absent.
    private func read(_ file: URL) throws -> Data? {
        do {
            return try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private func save(_ entries: [Entry], scope: Scope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL(scope: scope), options: .atomic)
        notifyChange()
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
