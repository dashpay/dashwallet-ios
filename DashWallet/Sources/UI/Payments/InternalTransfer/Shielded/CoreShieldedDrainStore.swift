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

    init(directory: URL? = nil) {
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
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func remove(_ operation: CoreShieldedDrainOperation) throws {
        guard let existing = try load(operation.context) else { return }
        guard existing == operation else { throw StoreError.pendingOperation }
        try FileManager.default.removeItem(at: file(operation.context))
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
