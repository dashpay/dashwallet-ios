import Foundation
import SwiftDashSDK
import SwiftData

/// Both launch restoration and live readback use the persisted address rows.
/// Fetch failures throw; a missing wallet or Platform account returns nil.
/// The caller supplies the network-specific container from SwiftDashSDKHost.
/// Address rows are wallet-scoped within that separate database.
@MainActor
enum PlatformBalanceReader {
    struct Snapshot {
        let addresses: [PersistentPlatformAddress]
        let credits: UInt64
        var activeAddressCount: Int { addresses.filter { $0.balance > 0 }.count }
    }

    enum ReadError: Error {
        case amountOverflow
    }

    static func read(
        container: ModelContainer, walletId: Data, network: Network
    ) throws -> Snapshot? {
        let networkRaw = network.rawValue
        var walletQuery = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId && $0.networkRaw == networkRaw })
        walletQuery.fetchLimit = 1
        guard let wallet = try container.mainContext.fetch(walletQuery).first,
              wallet.accounts.contains(where: { $0.accountType == 14 }) else { return nil }

        let addresses = try container.mainContext.fetch(FetchDescriptor<PersistentPlatformAddress>(
            predicate: PersistentPlatformAddress.predicate(walletId: walletId),
            sortBy: [SortDescriptor(\.accountIndex), SortDescriptor(\.addressIndex)]))
        let credits = try addresses.reduce(UInt64(0)) { total, row in
            let sum = total.addingReportingOverflow(row.balance)
            guard !sum.overflow else { throw ReadError.amountOverflow }
            return sum.partialValue
        }
        return Snapshot(addresses: addresses, credits: credits)
    }
}
