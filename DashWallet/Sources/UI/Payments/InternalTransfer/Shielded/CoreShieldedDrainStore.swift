import Foundation

struct CoreShieldedDrainContext: Codable, Equatable, Sendable {
    let walletId: Data
    let networkScope: String
}

struct CoreShieldedDrainOperation: Codable, Equatable, Sendable {
    let id: UUID
    let context: CoreShieldedDrainContext
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
