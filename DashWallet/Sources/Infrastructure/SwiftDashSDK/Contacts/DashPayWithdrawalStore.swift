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

    struct Scope: Codable, Hashable {
        let networkRaw: Int
        let walletId: Data
        let ownerIdentityId: Data
        /// The chain within the network kind (`Network.persistenceScope`):
        /// named devnets share one kind.
        let chain: String

        init(networkRaw: Int, walletId: Data, ownerIdentityId: Data, chain: String? = nil) {
            self.networkRaw = networkRaw
            self.walletId = walletId
            self.ownerIdentityId = ownerIdentityId
            self.chain = chain ?? Self.kindChain(networkRaw)
        }

        init(_ recipient: ContactPaymentRecipient) {
            self.init(
                networkRaw: recipient.network.rawValue, walletId: recipient.walletId,
                ownerIdentityId: recipient.ownerIdentityId, chain: recipient.chain)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let networkRaw = try container.decode(Int.self, forKey: .networkRaw)
            self.init(
                networkRaw: networkRaw,
                walletId: try container.decode(Data.self, forKey: .walletId),
                ownerIdentityId: try container.decode(Data.self, forKey: .ownerIdentityId),
                chain: try container.decodeIfPresent(String.self, forKey: .chain))
        }

        /// The chain a network kind names on its own, as `persistenceScope`
        /// spells mainnet and testnet.
        static func kindChain(_ networkRaw: Int) -> String {
            switch WalletEnvironment.NetworkKind(rawValue: networkRaw) {
            case .mainnet: return "mainnet"
            case .testnet: return "testnet"
            case .devnet: return "devnet"
            case nil: return "\(networkRaw)"
            }
        }
    }

    enum Source: String, Codable {
        case platform
        case shielded
    }

    enum Status: String, Codable {
        /// Persisted before the SDK reserves the contact's address, so a
        /// reservation is counted even when its record can't be completed.
        /// Nothing was submitted from this state.
        case reserving
        /// The address was reserved but the withdrawal was proven never
        /// submitted. Kept so `unpaidReservationStreak` can bound how many of
        /// the contact's addresses go unpaid.
        case unused
        /// Persisted before invoking the opaque withdrawal SDK call. A crash
        /// can leave this state behind even if submission succeeded.
        case submitting
        /// SDK accepted the withdrawal; the Core payout is still asynchronous.
        case submitted
        /// Submission was attempted but its result could not be established.
        case unconfirmed
        /// Not a withdrawal: the contact was paid from the Core balance. Kept
        /// only to end an unpaid streak (`unpaidReservationStreak`).
        case corePayment
    }

    /// What the SDK's Shielded activity says about a Shielded withdrawal. The
    /// SDK records its Pending row just before the spend is dispatched, and
    /// can re-broadcast the spend while that row stays Pending; a stranded
    /// spend it releases is flipped to Failed.
    enum ShieldedSpendState {
        case pending
        case confirmed
        case failed
        /// No row, or one the user stopped recovering (Unknown): nothing is
        /// re-broadcast, but the row is written best-effort.
        case unrecorded
    }

    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let scope: Scope
        let contactIdentityId: Data
        var address: String
        let amountDuffs: UInt64
        let amountIsEstimate: Bool
        let source: Source
        let createdAt: Date
        var status: Status
        /// The Core chain tip when the attempt was recorded, or when the lock
        /// was first checked with a known tip.
        var coreHeight: UInt32?

        /// A withdrawal that was, or may have been, submitted: what the
        /// contact's payment history shows.
        var mayHaveBeenSubmitted: Bool {
            status == .submitting || status == .submitted || status == .unconfirmed
        }
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
    private let removeItem: (URL) throws -> Void

    init(
        directory: URL,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.directory = directory
        self.removeItem = removeItem
    }

    /// Call after authorization, immediately BEFORE asking the SDK to reserve
    /// the contact's address. A failed save must prevent the reservation. Keep
    /// the captured scope through awaits so a wallet switch cannot relabel it.
    func beginReservation(
        scope: Scope,
        contactIdentityId: Data,
        amountDuffs: UInt64,
        amountIsEstimate: Bool = false,
        source: Source,
        coreHeight: UInt32? = nil
    ) throws -> Entry {
        guard scope.walletId.count == 32, scope.ownerIdentityId.count == 32,
              contactIdentityId.count == 32, amountDuffs > 0,
              WalletEnvironment.NetworkKind(rawValue: scope.networkRaw) != nil else {
            throw StoreError.invalidPayment
        }
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: scope)
        let entry = Entry(
            id: UUID(), scope: scope, contactIdentityId: contactIdentityId,
            address: "", amountDuffs: amountDuffs,
            amountIsEstimate: amountIsEstimate, source: source,
            createdAt: Date(), status: .reserving, coreHeight: coreHeight)
        entries.append(entry)
        try save(entries, scope: scope)
        return entry
    }

    /// Records the reserved address, immediately BEFORE invoking the
    /// withdrawal. A failed save must prevent submission.
    func recordReservedAddress(_ reservation: Entry, address: String) throws -> Entry {
        guard reservation.status == .reserving, !address.isEmpty else { throw StoreError.invalidPayment }
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: reservation.scope)
        guard let index = entries.firstIndex(where: { $0.id == reservation.id }) else {
            throw StoreError.missingEntry
        }
        entries[index].address = address
        entries[index].status = .submitting
        try save(entries, scope: reservation.scope)
        return entries[index]
    }

    func begin(
        scope: Scope,
        contactIdentityId: Data,
        address: String,
        amountDuffs: UInt64,
        amountIsEstimate: Bool = false,
        source: Source,
        coreHeight: UInt32? = nil
    ) throws -> Entry {
        guard !address.isEmpty else { throw StoreError.invalidPayment }
        let reservation = try beginReservation(
            scope: scope, contactIdentityId: contactIdentityId,
            amountDuffs: amountDuffs, amountIsEstimate: amountIsEstimate, source: source,
            coreHeight: coreHeight)
        return try recordReservedAddress(reservation, address: address)
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

    /// Core blocks an unresolved attempt stays locked for, besides the
    /// device-clock window: about a day at 2.5 minutes a block. A clock that
    /// jumps forward does not move the chain.
    static let lockBlocks: UInt32 = 576

    /// True when a withdrawal to this contact was never confirmed as
    /// submitted (`.submitting` or `.unconfirmed`) and may still execute: one
    /// recorded since `date` or fewer than `lockBlocks` Core blocks before
    /// `coreHeight` — an unknown tip keeps it locked — or a Shielded one of
    /// any age the SDK still holds Pending: it keeps re-broadcasting that
    /// spend on later syncs, whatever the device clock says. A Shielded one
    /// the SDK confirmed or failed is resolved at any age. An attempt recorded
    /// without a tip starts counting from the first check that has one.
    /// `shieldedSpendState` is called without the store lock held.
    func hasUnresolvedEntry(
        scope: Scope,
        contactIdentityId: Data,
        since date: Date,
        coreHeight: UInt32? = nil,
        shieldedSpendState: (Entry) -> ShieldedSpendState = { _ in .pending }
    ) throws -> Bool {
        try unresolvedEntriesStampingHeight(coreHeight, scope: scope, contactIdentityId: contactIdentityId)
            .contains { entry in
                let isRecent = entry.createdAt >= date || !Self.chainAdvanced(from: entry.coreHeight, to: coreHeight)
                guard entry.source == .shielded else { return isRecent }
                switch shieldedSpendState(entry) {
                case .pending: return true
                case .confirmed, .failed: return false
                case .unrecorded: return isRecent
                }
            }
    }

    static func chainAdvanced(from start: UInt32?, to tip: UInt32?) -> Bool {
        guard let start, let tip else { return false }
        return UInt64(tip) >= UInt64(start) + UInt64(lockBlocks)
    }

    private func unresolvedEntriesStampingHeight(
        _ coreHeight: UInt32?,
        scope: Scope,
        contactIdentityId: Data
    ) throws -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: scope)
        let unresolved = entries.indices.filter {
            entries[$0].scope == scope && entries[$0].contactIdentityId == contactIdentityId
                && (entries[$0].status == .submitting || entries[$0].status == .unconfirmed)
        }
        if let coreHeight {
            let unstamped = unresolved.filter { entries[$0].coreHeight == nil }
            if !unstamped.isEmpty {
                unstamped.forEach { entries[$0].coreHeight = coreHeight }
                try save(entries, scope: scope)
            }
        }
        return unresolved.map { entries[$0] }
    }

    /// How many of the contact's addresses the latest attempts reserved
    /// without evidence that one was paid. The contact's wallet only looks a
    /// fixed number of addresses past the last one paid, so only that
    /// evidence ends the run: a withdrawal the SDK accepted (`.submitted`)
    /// and didn't later fail, a Shielded one it confirmed, or a Core
    /// payment. An attempt whose outcome is unknown counts, whether or not
    /// it still locks the contact.
    ///
    /// Read in the order the entries were written, not by date: attempts in
    /// quick succession can share a timestamp. `shieldedSpendState` is
    /// called without the store lock held.
    func unpaidReservationStreak(
        scope: Scope,
        contactIdentityId: Data,
        shieldedSpendState: (Entry) -> ShieldedSpendState = { _ in .pending }
    ) throws -> Int {
        let written: [Entry]
        lock.lock()
        do {
            written = try load(scope: scope)
                .filter { $0.scope == scope && $0.contactIdentityId == contactIdentityId }
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        return written.reversed().prefix { entry in
            switch entry.status {
            case .reserving, .unused: return true
            case .corePayment: return false
            case .submitted: return entry.source == .shielded && shieldedSpendState(entry) == .failed
            case .submitting, .unconfirmed: return entry.source == .platform || shieldedSpendState(entry) != .confirmed
            }
        }.count
    }

    /// Records that the contact was paid from the Core balance, ending any
    /// unpaid streak: the Core payment pays the next of the contact's
    /// addresses, which their wallet then looks past.
    func recordCorePayment(scope: Scope, contactIdentityId: Data, amountDuffs: UInt64) throws {
        guard contactIdentityId.count == 32 else { throw StoreError.invalidPayment }
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(scope: scope)
        entries.append(Entry(
            id: UUID(), scope: scope, contactIdentityId: contactIdentityId,
            address: "", amountDuffs: amountDuffs, amountIsEstimate: false, source: .platform,
            createdAt: Date(), status: .corePayment))
        try save(entries, scope: scope)
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
        try sweepRetired(in: directory)
        try sweepRetired(in: directory.deletingLastPathComponent())
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
        // A leftover that cannot be deleted fails the wipe: it holds records.
        try sweepRetired(in: parent)
        try retire(directory, in: parent, skippingMissing: true)
        notifyChange()
    }

    /// Renames `url` out of the journal — the one step that drops its
    /// records — then deletes it. A deletion that fails renames what is left
    /// back, so the records still read and the clear or wipe throws; only a
    /// copy a crash left behind is found by the next sweep.
    /// `skippingMissing` skips a `url` that was never created; a deletion
    /// failing with "no such file" still throws.
    private func retire(_ url: URL, in parent: URL, skippingMissing: Bool = false) throws {
        let retired = parent.appendingPathComponent(
            "\(retiredPrefix)\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.moveItem(at: url, to: retired)
        } catch CocoaError.fileNoSuchFile where skippingMissing {
            return
        }
        do {
            try removeItem(retired)
        } catch {
            try FileManager.default.moveItem(at: retired, to: url)
            throw error
        }
    }

    /// Throws when a leftover cannot be deleted, or `parent` cannot be
    /// listed for any reason but its absence: either way records may survive.
    private func sweepRetired(in parent: URL) throws {
        let leftovers: [URL]
        do {
            leftovers = try FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return
        }
        for leftover in leftovers where leftover.lastPathComponent.hasPrefix(retiredPrefix) {
            try removeItem(leftover)
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

    /// `<network>[-<chain>]_<walletHex>_<ownerHex>.json` → `walletHex`. Read
    /// from the end: a devnet's name may itself contain `_`.
    private static func walletHex(ofFile url: URL) -> String? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        return parts.count >= 3 ? String(parts[parts.count - 2]) : nil
    }

    /// A chain other than its kind's own (a named devnet) is part of the
    /// name, so two devnets never share a journal.
    private func fileURL(scope: Scope) -> URL {
        let chain = scope.chain == Scope.kindChain(scope.networkRaw) ? "" : "-\(scope.chain)"
        return directory.appendingPathComponent(
            "\(scope.networkRaw)\(chain)_\(Self.hex(scope.walletId))_\(Self.hex(scope.ownerIdentityId)).json")
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
