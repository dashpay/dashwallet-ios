import Foundation

/// Local provenance for DashPay payments funded by a Platform withdrawal.
/// These are submission records, never Core transaction IDs or proof that a
/// recipient has received funds. The withdrawal SDK does not return a Core
/// transaction ID. Keep this journal separate from its Core payment history.
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
                return NSLocalizedString("Unable to save this DashPay withdrawal.", comment: "")
            case .missingEntry:
                return NSLocalizedString("The DashPay withdrawal record is unavailable.", comment: "")
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
              (0...2).contains(scope.networkRaw) else {
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

    func clearForWallet(walletId: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let walletHex = Self.hex(walletId)
        for file in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        where file.lastPathComponent.split(separator: "_").dropFirst().first.map(String.init) == walletHex {
            try FileManager.default.removeItem(at: file)
        }
        notifyChange()
    }

    func resetForWipe() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        notifyChange()
    }

    private func fileURL(scope: Scope) -> URL {
        directory.appendingPathComponent(
            "\(scope.networkRaw)_\(Self.hex(scope.walletId))_\(Self.hex(scope.ownerIdentityId)).json")
    }

    private func load(scope: Scope) throws -> [Entry] {
        let url = fileURL(scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        // Do not overwrite corrupt/unreadable history with an empty journal.
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
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
