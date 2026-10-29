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
        let data: Data
        do {
            data = try Data(contentsOf: fileURL(scope: scope))
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        // Anything but a missing file throws: `fileExists` also answers false
        // when existence can't be determined, and an unreadable journal must
        // lock contact payments rather than read as empty. Nor is corrupt
        // history overwritten with an empty one.
        return try JSONDecoder().decode([Entry].self, from: data)
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
