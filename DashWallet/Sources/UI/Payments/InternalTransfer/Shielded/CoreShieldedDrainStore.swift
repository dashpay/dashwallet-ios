import Foundation

struct CoreShieldedDrainContext: Codable, Equatable, Sendable {
    let walletId: Data
    let networkScope: String
}

/// Who the drain pays. The SDK does not persist the Orchard recipient of an
/// asset lock: a resume submits to whatever recipient is passed on that call,
/// so this is the only durable record of where the lock must go. Every resume
/// of a drain operation reads it from here.
enum CoreShieldedDrainRecipient: Equatable, Sendable {
    /// The wallet's own default Orchard address, re-derived at resume time.
    case ownWallet
    /// A recipient outside this wallet, by raw 43-byte Orchard payload.
    case external(raw43: Data)

    static let externalRaw43Count = 43

    /// The payload to hand the SDK, or nil when the wallet's own address is
    /// resolved by the caller.
    var externalRaw43: Data? {
        if case .external(let raw43) = self { return raw43 }
        return nil
    }

    var isExternal: Bool { externalRaw43 != nil }
}

extension UUID {
    /// The SDK stores the drain operation UUID as its 16 raw bytes
    /// (`PersistentAssetLock.operationId`). Anything else is not an id.
    init?(drainOperationIdBytes bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self.init(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }
}

struct CoreShieldedDrainOperation: Codable, Equatable, Sendable {
    let id: UUID
    let context: CoreShieldedDrainContext
    let recipient: CoreShieldedDrainRecipient

    init(id: UUID, context: CoreShieldedDrainContext, recipient: CoreShieldedDrainRecipient = .ownWallet) {
        self.id = id
        self.context = context
        self.recipient = recipient
    }

    private enum CodingKeys: String, CodingKey {
        case id, context, recipientKind, recipientRaw43
    }

    private enum RecipientKind: String, Codable {
        case own, external
    }

    /// Markers written before the recipient existed carry neither key. They
    /// were only ever written by the own-wallet Max, so that exact pair
    /// decodes as `.ownWallet`. This marker is the only record of where an
    /// external drain pays, so every other combination of the two keys that
    /// does not spell a complete recipient is corruption, never a default:
    /// a payload without a kind, an `own` kind with a payload, an `external`
    /// kind without one, or a payload of the wrong size.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        context = try container.decode(CoreShieldedDrainContext.self, forKey: .context)
        let kind = try container.decodeIfPresent(RecipientKind.self, forKey: .recipientKind)
        let raw43 = try container.decodeIfPresent(Data.self, forKey: .recipientRaw43)
        switch (kind, raw43) {
        case (nil, nil), (.own, nil):
            recipient = .ownWallet
        case (.external, let raw43?):
            guard raw43.count == CoreShieldedDrainRecipient.externalRaw43Count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .recipientRaw43, in: container,
                    debugDescription: "external recipient must be \(CoreShieldedDrainRecipient.externalRaw43Count) bytes, was \(raw43.count)")
            }
            recipient = .external(raw43: raw43)
        case (nil, _?), (.own, _?):
            throw DecodingError.dataCorruptedError(
                forKey: .recipientRaw43, in: container,
                debugDescription: "recipient payload without an external kind")
        case (.external, nil):
            throw DecodingError.keyNotFound(
                CodingKeys.recipientRaw43,
                DecodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "external recipient without a payload"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(context, forKey: .context)
        switch recipient {
        case .ownWallet:
            try container.encode(RecipientKind.own, forKey: .recipientKind)
        case .external(let raw43):
            try container.encode(RecipientKind.external, forKey: .recipientKind)
            try container.encode(raw43, forKey: .recipientRaw43)
        }
    }
}

/// Written before entering the SDK. A missing or unreadable SDK response never
/// removes this marker; only a definitive status for this UUID may do so.
protocol CoreShieldedDrainStoring {
    func load(_ context: CoreShieldedDrainContext) throws -> CoreShieldedDrainOperation?
    func save(_ operation: CoreShieldedDrainOperation) throws
    func remove(_ operation: CoreShieldedDrainOperation) throws
}

struct CoreShieldedDrainFileStore: CoreShieldedDrainStoring {
    let directory: URL

    private let flush: (URL) throws -> Void

    init(directory: URL? = nil, flush: @escaping (URL) throws -> Void = DurableFileStorage.flush) {
        self.flush = flush
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreShieldedDrain", isDirectory: true)
    }

    private func file(_ context: CoreShieldedDrainContext) -> URL {
        let wallet = context.walletId.map { String(format: "%02x", $0) }.joined()
        // Hex encoding keeps even a named devnet within this directory.
        let scope = context.networkScope.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(wallet)-\(scope).json")
    }

    func load(_ context: CoreShieldedDrainContext) throws -> CoreShieldedDrainOperation? {
        let data: Data
        do {
            data = try Data(contentsOf: file(context))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        let operation = try JSONDecoder().decode(CoreShieldedDrainOperation.self, from: data)
        guard operation.context == context else { throw StoreError.contextMismatch }
        return operation
    }

    func save(_ operation: CoreShieldedDrainOperation) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing = try load(operation.context), existing != operation {
            throw StoreError.pendingOperation
        }
        let destination = file(operation.context)
        try JSONEncoder().encode(operation).write(to: destination, options: .atomic)
        try flush(destination)
        // The atomic rename and every potentially new ancestor must reach disk
        // before the SDK may dispatch. Flush existing ancestors too: an earlier
        // failed save may have created them without completing its barrier.
        // The OS-created app container is the durable boundary; never open
        // directories outside the iOS sandbox. Injected host-test locations
        // outside the home directory terminate at the filesystem root instead.
        let container = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        var ancestor = directory.standardizedFileURL
        while true {
            try flush(ancestor)
            if ancestor.path == container.path || ancestor.path == "/" { break }
            let parent = ancestor.deletingLastPathComponent().standardizedFileURL
            guard parent.path != ancestor.path else { break }
            ancestor = parent
        }
    }

    func remove(_ operation: CoreShieldedDrainOperation) throws {
        guard let existing = try load(operation.context) else { return }
        guard existing == operation else { throw StoreError.pendingOperation }
        try FileManager.default.removeItem(at: file(operation.context))
    }

    /// Successful deletion of one scope must not erase another scope's UUID.
    func clear(context: CoreShieldedDrainContext) throws {
        let url = file(context)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func clear(walletId: Data? = nil) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        if let walletId {
            let prefix = walletId.map { String(format: "%02x", $0) }.joined() + "-"
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix(prefix) {
                try FileManager.default.removeItem(at: url)
            }
        } else {
            try FileManager.default.removeItem(at: directory)
        }
    }

    enum StoreError: LocalizedError {
        case contextMismatch, pendingOperation
        var errorDescription: String? {
            NSLocalizedString("Check the pending Max transfer before starting another.", comment: "Core drain persistence guard")
        }
    }
}
