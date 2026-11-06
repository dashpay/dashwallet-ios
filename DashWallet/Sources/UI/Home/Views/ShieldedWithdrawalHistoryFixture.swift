#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import SwiftDashSDK
import SwiftUI
import UIKit

/// Isolated persistence-boundary fault injection. Uses no wallet runtime, seed,
/// network or production data; every displayed status comes from the production reader.
@MainActor
final class ShieldedWithdrawalHistoryFixture: ObservableObject {
    static let walletId = Data(repeating: 0x71, count: 32)
    static let script = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0x31), count: 20) + [0x88, 0xac])
    static let originalCredits: UInt64 = 10_000_000_000
    static let walletIdHex = walletId.map { String(format: "%02x", $0) }.joined()
    let container: ModelContainer
    let withdrawalStore: ShieldedWithdrawalStore
    @Published var items: [ShieldedActivityItem] = []
    @Published var balance: UInt64 = 0
    @Published var receiptCount = 0
    @Published var destinationTagged = false
    @Published var error: String?

    /// Creates the real SDK schema without CloudKit, in memory or at an isolated restartable URL.
    static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: DashModelContainer.schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(schema: DashModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: DashModelContainer.schema, configurations: [config])
    }

    /// Seeds only a new store; reopening preserves both activity state and destination tags.
    init(container: ModelContainer, withdrawalStore: ShieldedWithdrawalStore) throws {
        self.container = container
        self.withdrawalStore = withdrawalStore
        if try container.mainContext.fetchCount(FetchDescriptor<PersistentWallet>()) == 0 {
            let wallet = PersistentWallet(walletId: Self.walletId)
            let account = PersistentAccount(wallet: wallet, accountType: 0, accountIndex: 0, accountTypeName: "BIP44")
            let address = PersistentCoreAddress(address: Self.address, poolTypeTag: 0, addressIndex: 0, derivationPath: "fixture")
            address.account = account
            wallet.accounts = [account]
            account.coreAddresses = [address]
            container.mainContext.insert(wallet)
            container.mainContext.insert(account)
            container.mainContext.insert(address)
            container.mainContext.insert(PersistentShieldedNote(
                walletId: Self.walletId, accountIndex: 0, position: 0,
                cmx: Data(repeating: 0x32, count: 32), nullifier: Data(repeating: 0x33, count: 32),
                blockHeight: 1, isSpent: false, value: Self.originalCredits, noteData: Data()))
            try container.mainContext.save()
        }
        try reload()
    }

    static var address: String {
        // Same codec and network selection as the production withdrawal reader.
        ScriptAddressCodec.address(forScript: script, network: WalletEnvironment.isMainnet ? .mainnet : .testnet)!
    }

    /// Persists an SDK-shaped outcome and immediately projects it through the production reader.
    @discardableResult
    func insertActivity(id: UInt8, kind: Int = 5, status: Int = 0, amount: UInt64 = ShieldedWithdrawalHistoryFixture.originalCredits,
                        counterparty: Data = ShieldedWithdrawalHistoryFixture.script) throws -> PersistentShieldedActivity {
        let row = PersistentShieldedActivity(
            walletId: Self.walletId, accountIndex: 0, entryId: Data(repeating: id, count: 32),
            kindTag: kind, direction: 1, status: status, amount: amount, fee: 1000, hasFee: true,
            blockHeight: 0, hasBlockHeight: false, createdAtMs: 1_800_000_000_000,
            identityId: Data(), counterparty: counterparty, memo: Data(), noteCmxs: Data(),
            spentNullifiers: Data(repeating: id, count: 32))
        container.mainContext.insert(row)
        try container.mainContext.save()
        try reload()
        return row
    }

    /// Injects a status update into the existing activity instead of replacing its identity.
    func setStatus(_ status: Int, id: UInt8 = 1) throws {
        let key = Data(repeating: id, count: 32)
        let row = try container.mainContext.fetch(FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate { $0.entryId == key })).first
        guard let row else { throw CocoaError(.fileNoSuchFile) }
        row.status = status
        try container.mainContext.save()
        try reload()
    }

    /// Persists an owned Core output at the same destination used by the shielded attempts.
    func insertReceipt(id: UInt8 = 0x70, amountDuffs: UInt64 = 5_000_000) throws {
        let transaction = PersistentTransaction(txid: Data(repeating: id, count: 32), transactionData: Data(),
            context: 2, blockHeight: 100, direction: 0, netAmount: Int64(amountDuffs), firstSeen: 1_800_000_001)
        let output = PersistentTxo(transaction: transaction, vout: 0, amount: amountDuffs,
                                   address: Self.address, scriptPubKey: Self.script, height: 100)
        let address = try container.mainContext.fetch(FetchDescriptor<PersistentCoreAddress>()).first
        output.coreAddress = address
        output.walletId = Self.walletId
        transaction.outputs = [output]
        container.mainContext.insert(transaction)
        container.mainContext.insert(output)
        try container.mainContext.save()
        try reload()
    }

    /// Re-reads saved models and reconciles the real destination store before publishing UI state.
    func reload() throws {
        let context = ModelContext(container)
        let receipts = try context.fetch(FetchDescriptor<PersistentTransaction>())
        items = SwiftDashSDKWalletSource.fetchShieldedActivity(
            container: container, walletId: Self.walletId,
            coreTransactions: receipts.map { Transaction(persistentTransaction: $0, walletId: Self.walletId) },
            withdrawalStore: withdrawalStore)
            .sorted { $0.id < $1.id }
        balance = try context.fetch(FetchDescriptor<PersistentShieldedNote>(
            predicate: PersistentShieldedNote.unspentPredicate(walletId: Self.walletId))).reduce(0) { $0 + $1.value }
        receiptCount = receipts.count
        destinationTagged = withdrawalStore.contains(Self.address, walletIdHex: Self.walletIdHex)
    }

    /// Keeps fixture failures visible to UI tests instead of silently losing an injection.
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = String(describing: error) }
    }
}

@objc(DWShieldedHistoryUITestFixture)
final class DWShieldedHistoryUITestFixture: NSObject {
    /// Opts into an isolated, UUID-scoped fixture before real wallet initialization.
    @MainActor @objc static func makeViewControllerIfRequested() -> UIViewController? {
        guard let run = ProcessInfo.processInfo.environment["SHIELDED_HISTORY_UI_TEST"],
              let id = UUID(uuidString: run) else { return nil }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shielded-history-\(id.uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let defaults = UserDefaults(suiteName: "shielded-history-\(id.uuidString)") else {
                throw CocoaError(.fileWriteUnknown)
            }
            let fixture = try ShieldedWithdrawalHistoryFixture(
                container: ShieldedWithdrawalHistoryFixture.makeContainer(url: directory.appendingPathComponent("history.store")),
                withdrawalStore: ShieldedWithdrawalStore(defaults: defaults))
            return UIHostingController(rootView: ShieldedHistoryFixtureView(fixture: fixture))
        } catch {
            return UIHostingController(rootView: Text("Fixture setup failed: \(error)"))
        }
    }
}

private struct ShieldedHistoryFixtureView: View {
    @ObservedObject var fixture: ShieldedWithdrawalHistoryFixture
    @State private var selected: ShieldedActivityItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    Text("Shielded credits: \(fixture.balance)").accessibilityIdentifier("fixtureBalance")
                    Text("Core receipts: \(fixture.receiptCount)").accessibilityIdentifier("fixtureReceipts")
                    Text("Destination tagged: \(fixture.destinationTagged ? "yes" : "no")")
                        .accessibilityIdentifier("fixtureDestinationTagged")
                    ForEach(fixture.items) { item in
                        ShieldedActivityHistoryRow(item: item, icon: AnyView(Image(systemName: "shield.fill"))) { selected = item }
                    }
                    Button("Record pending withdrawal") { fixture.perform { try fixture.insertActivity(id: 1) } }
                        .accessibilityIdentifier("recordPending")
                    Button("Inject definitive rejection") { fixture.perform { try fixture.setStatus(2) } }
                        .accessibilityIdentifier("injectFailure")
                    Button("Confirm withdrawal") { fixture.perform { try fixture.setStatus(1) } }
                        .accessibilityIdentifier("confirmWithdrawal")
                    Button("Record restored failed withdrawal") { fixture.perform { try fixture.insertActivity(id: 3, kind: 7, status: 2) } }
                        .accessibilityIdentifier("recordRestoredFailure")
                    Button("Record smaller confirmed withdrawal") {
                        fixture.perform { try fixture.insertActivity(id: 2, status: 1, amount: 5_000_000_000) }
                    }.accessibilityIdentifier("recordSmaller")
                    Button("Persist Core receipt") { fixture.perform { try fixture.insertReceipt() } }
                        .accessibilityIdentifier("recordReceipt")
                    Button("Reload history") { fixture.perform { try fixture.reload() } }
                        .accessibilityIdentifier("reloadHistory")
                    if let error = fixture.error { Text(error).accessibilityIdentifier("fixtureError") }
                }.padding()
            }
            .navigationTitle("History regression")
            .sheet(item: $selected) { item in
                NavigationStack {
                    ScrollView { ShieldedActivityDetailsView(item: item) }
                        .toolbar { Button("Close") { selected = nil }.accessibilityIdentifier("closeDetails") }
                }
            }
        }
    }
}
#endif
