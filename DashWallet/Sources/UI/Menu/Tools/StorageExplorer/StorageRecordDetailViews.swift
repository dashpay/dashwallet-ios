import SwiftUI
import SwiftData
import SwiftDashSDK

// MARK: - Shared Helpers

private struct FieldRow: View {
    let label: String
    let value: String
    @State private var didCopy: Bool = false

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            if didCopy {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = value
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        }
    }
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private func dateString(_ date: Date?) -> String {
    guard let date = date else { return "None" }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private func jsonString(_ data: Data?) -> String? {
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: pretty, encoding: .utf8) else { return nil }
    return str
}

// MARK: - PersistentIdentity

struct IdentityStorageDetailView: View {
    let record: PersistentIdentity

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "ID (Base58)", value: record.identityIdBase58)
                FieldRow(label: "ID (Hex)", value: record.identityIdString)
                FieldRow(label: "Balance", value: record.formattedBalance)
                FieldRow(label: "Revision", value: "\(record.revision)")
                FieldRow(label: "Is Local", value: record.isLocal ? "Yes" : "No")
                FieldRow(label: "Network", value: record.network.networkName)
            }
            Section("Names") {
                FieldRow(label: "Alias", value: record.alias ?? "None")
                FieldRow(label: "DPNS Name", value: record.dpnsName ?? "None")
                FieldRow(label: "Main DPNS Name", value: record.mainDpnsName ?? "None")
            }
            Section("Keys") {
                FieldRow(label: "Owner Key", value: record.ownerPrivateKeyIdentifier != nil ? "Present" : "Not set")
                FieldRow(label: "Voting Key", value: record.votingPrivateKeyIdentifier != nil ? "Present" : "Not set")
                FieldRow(label: "Payout Key", value: record.payoutPrivateKeyIdentifier != nil ? "Present" : "Not set")
            }
            Section("Relationships") {
                FieldRow(label: "Public Keys", value: "\(record.publicKeys.count)")
                FieldRow(label: "Documents", value: "\(record.documents.count)")
                FieldRow(label: "Token Balances", value: "\(record.tokenBalances.count)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
                FieldRow(label: "Synced", value: dateString(record.lastSyncedAt))
            }
        }
        .navigationTitle("Identity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDocument

struct DocumentStorageDetailView: View {
    let record: PersistentDocument

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Document ID", value: record.documentId)
                FieldRow(label: "Type", value: record.documentType)
                FieldRow(label: "Revision", value: "\(record.revision)")
                FieldRow(label: "Contract ID", value: record.contractId)
                FieldRow(label: "Owner ID", value: record.ownerId)
                FieldRow(label: "Network", value: record.network.networkName)
                FieldRow(label: "Deleted", value: record.isDeleted ? "Yes" : "No")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.localCreatedAt))
                FieldRow(label: "Updated", value: dateString(record.localUpdatedAt))
            }
            if let json = jsonString(record.data) {
                Section("Data") {
                    Text(json).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDataContract

struct DataContractStorageDetailView: View {
    let record: PersistentDataContract

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "ID (Base58)", value: record.idBase58)
                FieldRow(label: "Name", value: record.name)
                FieldRow(label: "Version", value: record.version.map { "\($0)" } ?? "None")
                FieldRow(label: "Owner (Base58)", value: record.ownerIdBase58 ?? "None")
                FieldRow(label: "Network", value: record.network.networkName)
                FieldRow(label: "Has Tokens", value: record.hasTokens ? "Yes" : "No")
            }
            Section("Flags") {
                FieldRow(label: "Can Be Deleted", value: record.canBeDeleted ? "Yes" : "No")
                FieldRow(label: "Read Only", value: record.readonly ? "Yes" : "No")
                FieldRow(label: "Keeps History", value: record.keepsHistory ? "Yes" : "No")
            }
            Section("Relationships") {
                FieldRow(label: "Document Types", value: "\(record.documentTypes?.count ?? 0)")
                FieldRow(label: "Tokens", value: "\(record.tokens?.count ?? 0)")
                FieldRow(label: "Documents", value: "\(record.documents.count)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
                FieldRow(label: "Accessed", value: dateString(record.lastAccessedAt))
                FieldRow(label: "Synced", value: dateString(record.lastSyncedAt))
            }
            Section("Serialized") {
                FieldRow(label: "Contract Size", value: "\(record.serializedContract.count) bytes")
            }
        }
        .navigationTitle("Data Contract")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentPublicKey

struct PublicKeyStorageDetailView: View {
    let record: PersistentPublicKey

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Key ID", value: "\(record.keyId)")
                FieldRow(label: "Purpose", value: record.purpose)
                FieldRow(label: "Security Level", value: record.securityLevel)
                FieldRow(label: "Key Type", value: record.keyType)
                FieldRow(label: "Read Only", value: record.readOnly ? "Yes" : "No")
                FieldRow(label: "Disabled At", value: record.disabledAt.map { "\($0)" } ?? "No")
            }
            Section("Data") {
                FieldRow(label: "Public Key", value: hexString(record.publicKeyData))
                FieldRow(label: "Private Key", value: record.hasPrivateKeyIdentifier ? "Present" : "Not set")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Accessed", value: dateString(record.lastAccessed))
            }
        }
        .navigationTitle("Public Key")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentToken

struct TokenStorageDetailView: View {
    let record: PersistentToken

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "ID", value: hexString(record.id))
                FieldRow(label: "Contract (Base58)", value: record.contractIdBase58)
                FieldRow(label: "Name", value: record.name)
                FieldRow(label: "Position", value: "\(record.position)")
                FieldRow(label: "Decimals", value: "\(record.decimals)")
                FieldRow(label: "Base Supply", value: record.formattedBaseSupply)
                FieldRow(label: "Paused", value: record.isPaused ? "Yes" : "No")
            }
            Section("Relationships") {
                FieldRow(label: "Balances", value: "\(record.balances?.count ?? 0)")
                FieldRow(label: "History Events", value: "\(record.historyEvents?.count ?? 0)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdatedAt))
            }
        }
        .navigationTitle("Token")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentTokenBalance

struct TokenBalanceStorageDetailView: View {
    let record: PersistentTokenBalance

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Token ID", value: record.tokenId)
                FieldRow(label: "Identity ID", value: hexString(record.identityId))
                FieldRow(label: "Balance", value: "\(record.balance)")
                FieldRow(label: "Frozen", value: record.frozen ? "Yes" : "No")
                FieldRow(label: "Network", value: record.network.networkName)
            }
            Section("Token Info") {
                FieldRow(label: "Name", value: record.tokenName ?? "None")
                FieldRow(label: "Symbol", value: record.tokenSymbol ?? "None")
                FieldRow(label: "Decimals", value: record.tokenDecimals.map { "\($0)" } ?? "None")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
                FieldRow(label: "Synced", value: dateString(record.lastSyncedAt))
            }
        }
        .navigationTitle("Token Balance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentTokenHistoryEvent

struct TokenHistoryStorageDetailView: View {
    let record: PersistentTokenHistoryEvent

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Event Type", value: record.eventType)
                FieldRow(label: "Transaction ID", value: record.transactionId.map { hexString($0) } ?? "None")
                FieldRow(label: "Block Height", value: record.blockHeight.map { "\($0)" } ?? "None")
                FieldRow(label: "Amount", value: record.amount.map { "\($0)" } ?? "None")
            }
            Section("Parties") {
                FieldRow(label: "From", value: record.fromIdentity.map { hexString($0) } ?? "None")
                FieldRow(label: "To", value: record.toIdentity.map { hexString($0) } ?? "None")
                FieldRow(label: "Performed By", value: hexString(record.performedByIdentity))
            }
            Section("Balance") {
                FieldRow(label: "Before", value: record.balanceBefore.map { "\($0)" } ?? "None")
                FieldRow(label: "After", value: record.balanceAfter.map { "\($0)" } ?? "None")
            }
            Section("Timestamps") {
                FieldRow(label: "Event", value: dateString(record.eventTimestamp))
                FieldRow(label: "Created", value: dateString(record.createdAt))
            }
        }
        .navigationTitle("Token History Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDocumentType

struct DocumentTypeStorageDetailView: View {
    let record: PersistentDocumentType

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Name", value: record.name)
                FieldRow(label: "Contract (Base58)", value: record.contractIdBase58)
            }
            Section("Flags") {
                FieldRow(label: "Keeps History", value: record.documentsKeepHistory ? "Yes" : "No")
                FieldRow(label: "Mutable", value: record.documentsMutable ? "Yes" : "No")
                FieldRow(label: "Can Be Deleted", value: record.documentsCanBeDeleted ? "Yes" : "No")
            }
            Section("Relationships") {
                FieldRow(label: "Properties", value: "\(record.propertiesList?.count ?? 0)")
                FieldRow(label: "Indices", value: "\(record.indices?.count ?? 0)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Accessed", value: dateString(record.lastAccessedAt))
            }
        }
        .navigationTitle("Document Type")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentIndex

struct IndexStorageDetailView: View {
    let record: PersistentIndex

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Name", value: record.name)
                FieldRow(label: "Document Type", value: record.documentTypeName)
                FieldRow(label: "Unique", value: record.unique ? "Yes" : "No")
                FieldRow(label: "Null Searchable", value: record.nullSearchable ? "Yes" : "No")
                FieldRow(label: "Contested", value: record.contested ? "Yes" : "No")
            }
            if let props = record.properties, !props.isEmpty {
                Section("Properties") {
                    ForEach(props, id: \.self) { prop in
                        Text(prop).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
            }
        }
        .navigationTitle("Index")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentProperty

struct PropertyStorageDetailView: View {
    let record: PersistentProperty

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Name", value: record.name)
                FieldRow(label: "Type", value: record.type)
                FieldRow(label: "Document Type", value: record.documentTypeName)
                FieldRow(label: "Required", value: record.isRequired ? "Yes" : "No")
            }
            Section("Constraints") {
                if let v = record.minLength { FieldRow(label: "Min Length", value: "\(v)") }
                if let v = record.maxLength { FieldRow(label: "Max Length", value: "\(v)") }
                if let v = record.pattern { FieldRow(label: "Pattern", value: v) }
                if let v = record.format { FieldRow(label: "Format", value: v) }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
            }
        }
        .navigationTitle("Property")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentKeyword

struct KeywordStorageDetailView: View {
    let record: PersistentKeyword

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Keyword", value: record.keyword)
                if let contract = record.dataContract {
                    FieldRow(label: "Contract", value: contract.name)
                }
            }
        }
        .navigationTitle("Keyword")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentPlatformAddressesSyncState

struct SyncStateStorageDetailView: View {
    let record: PersistentPlatformAddressesSyncState

    private var blockDate: Date? {
        record.syncTimestamp > 0
            ? Date(timeIntervalSince1970: TimeInterval(record.syncTimestamp))
            : nil
    }

    var body: some View {
        Form {
            Section("Sync Watermark") {
                FieldRow(label: "Network", value: record.network.networkName)
                FieldRow(label: "Sync Height", value: "\(record.syncHeight)")
                FieldRow(label: "Sync Timestamp", value: "\(record.syncTimestamp)")
                if let date = blockDate {
                    FieldRow(label: "Local Time", value: date.formatted(date: .abbreviated, time: .standard))
                    FieldRow(label: "UTC", value: {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        f.timeZone = TimeZone(identifier: "UTC")
                        return f.string(from: date) + " UTC"
                    }())
                }
                FieldRow(label: "Last Known Recent Block", value: record.lastKnownRecentBlock > 0
                    ? "\(record.lastKnownRecentBlock)"
                    : "0 (no recent address activity)")
            }
            Section("Timestamps") {
                FieldRow(label: "Record Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Sync State")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentPlatformAddress

struct PlatformAddressDetailView: View {
    let record: PersistentPlatformAddress

    @State private var didCopyAddress: Bool = false

    var body: some View {
        Form {
            Section("Address") {
                // Tap-to-copy: writes the full address to UIPasteboard and
                // fires a success haptic. The row's value flashes "Copied!"
                // briefly so the action is discoverable without an icon
                // (textSelection still works for partial copies via long-press).
                FieldRow(
                    label: "Address",
                    value: didCopyAddress ? "Copied!" : record.address
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = record.address
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { didCopyAddress = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { didCopyAddress = false }
                    }
                }
                FieldRow(
                    label: "Type",
                    value: record.addressType == 0 ? "P2PKH" : "P2SH"
                )
                FieldRow(label: "Hash", value: hexString(record.addressHash))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
                FieldRow(label: "Index", value: "\(record.addressIndex)")
                FieldRow(label: "Derivation Path", value: record.derivationPath)
                FieldRow(label: "Used", value: record.isUsed ? "Yes" : "No")
            }
            Section("Public Key") {
                FieldRow(
                    label: "Bytes (hex)",
                    value: record.publicKey.isEmpty
                        ? "—"
                        : record.publicKey.map { String(format: "%02x", $0) }.joined()
                )
            }
            Section("Balance / Activity") {
                FieldRow(label: "Balance", value: "\(record.balance) credits")
                FieldRow(label: "Nonce", value: "\(record.nonce)")
                FieldRow(
                    label: "First Seen Height",
                    value: record.firstSeenHeight == 0 ? "—" : "\(record.firstSeenHeight)"
                )
                FieldRow(
                    label: "Last Seen Height",
                    value: record.lastSeenHeight == 0 ? "—" : "\(record.lastSeenHeight)"
                )
            }
            Section("Ownership") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Platform Address")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentWallet

struct WalletStorageDetailView: View {
    let record: PersistentWallet

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Network", value: record.network?.networkName ?? "—")
                FieldRow(label: "Name", value: record.name ?? "None")
                FieldRow(label: "Birth Height", value: "\(record.birthHeight)")
                FieldRow(label: "Synced Height", value: "\(record.syncedHeight)")
            }
            // Wallet-level cached balance fields were removed from
            // `PersistentWallet` (SDK comment: "Per-account totals continue
            // to live on `PersistentAccount`"). Sum the per-account fields
            // for display in the storage explorer; the canonical live total
            // lives in `PlatformWalletManager.accountBalances(for:)`.
            Section("Balance (summed across accounts)") {
                FieldRow(label: "Confirmed", value: "\(record.accounts.reduce(UInt64(0)) { $0 + $1.balanceConfirmed })")
                FieldRow(label: "Unconfirmed", value: "\(record.accounts.reduce(UInt64(0)) { $0 + $1.balanceUnconfirmed })")
            }
            Section("Relationships") {
                FieldRow(label: "Accounts", value: "\(record.accounts.count)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentAccount

struct AccountStorageDetailView: View {
    let record: PersistentAccount

    /// Base58check-encoded xpub/tpub for this account, derived from
    /// the stored ExtendedPubKey bytes. `nil` when the bytes are empty
    /// (account created before the xpub-persistence path landed) or
    /// decode fails.
    private var accountXpubString: String? {
        // `accountExtendedPubKeyBytes` is now `Data?` (`@Attribute(.unique)`,
        // nil for accounts created before the xpub-persistence path).
        guard let bytes = record.accountExtendedPubKeyBytes else { return nil }
        return PlatformWalletManager.accountExtendedPubKeyString(bytes: bytes)
    }

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Type", value: record.accountTypeName)
                FieldRow(label: "Type ID", value: "\(record.accountType)")
                FieldRow(label: "Index", value: "\(record.accountIndex)")
                FieldRow(
                    label: "Extended Public Key",
                    value: accountXpubString ?? "—"
                )
            }
            Section("Balance") {
                FieldRow(label: "Confirmed", value: "\(record.balanceConfirmed)")
                FieldRow(label: "Unconfirmed", value: "\(record.balanceUnconfirmed)")
            }
            Section("Address Pools") {
                FieldRow(label: "External Highest Used", value: "\(record.externalHighestUsed)")
                FieldRow(label: "Internal Highest Used", value: "\(record.internalHighestUsed)")
            }
            Section("Relationships") {
                FieldRow(label: "Addresses", value: "\(record.coreAddresses.count)")
                FieldRow(label: "Wallet", value: record.wallet.name ?? hexString(record.wallet.walletId))
            }
            ForEach(addressSections(), id: \.0) { poolName, addresses in
                Section("\(poolName) Addresses (\(addresses.count))") {
                    ForEach(addresses) { addr in
                        NavigationLink(destination: CoreAddressDetailView(record: addr)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addr.address)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack(spacing: 8) {
                                    Text("Index \(addr.addressIndex)")
                                    if addr.isUsed {
                                        Text("• used")
                                    }
                                    if addr.balance > 0 {
                                        Text("• \(addr.balance)")
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Group the account's addresses by pool-type tag and present in
    /// a stable order: External, Internal, Absent, Absent (Hardened).
    /// Empty sections are skipped.
    private func addressSections() -> [(String, [PersistentCoreAddress])] {
        let grouped = Dictionary(grouping: record.coreAddresses) { $0.poolTypeTag }
        let order: [(UInt8, String)] = [
            (0, "External"),
            (1, "Internal"),
            (2, "Absent"),
            (3, "Absent (Hardened)"),
        ]
        return order.compactMap { tag, name in
            guard let bucket = grouped[tag], !bucket.isEmpty else { return nil }
            let sorted = bucket.sorted { $0.addressIndex < $1.addressIndex }
            return (name, sorted)
        }
    }
}

// MARK: - PersistentCoreAddress

struct CoreAddressDetailView: View {
    let record: PersistentCoreAddress
    @State private var showCopiedToast = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section("Address") {
                    HStack {
                        Text("Address").foregroundColor(.secondary)
                        Spacer()
                        Text(record.address).lineLimit(1).truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = record.address
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedToast = false
                        }
                    }
                    FieldRow(label: "Pool", value: record.poolTypeName)
                    FieldRow(label: "Index", value: "\(record.addressIndex)")
                    FieldRow(label: "Derivation Path", value: record.derivationPath)
                    FieldRow(label: "Used", value: record.isUsed ? "Yes" : "No")
                }
                Section("Public Key") {
                    FieldRow(
                        label: "Bytes (hex)",
                        value: record.publicKey.isEmpty
                            ? "—"
                            : record.publicKey.map { String(format: "%02x", $0) }.joined()
                    )
                }
                Section("Balance / Activity") {
                    FieldRow(label: "Balance", value: "\(record.balance)")
                    FieldRow(
                        label: "First Seen Height",
                        value: record.firstSeenHeight == 0 ? "—" : "\(record.firstSeenHeight)"
                    )
                    FieldRow(
                        label: "Last Seen Height",
                        value: record.lastSeenHeight == 0 ? "—" : "\(record.lastSeenHeight)"
                    )
                }
                Section("Timestamps") {
                    FieldRow(label: "Created", value: dateString(record.createdAt))
                    FieldRow(label: "Updated", value: dateString(record.lastUpdated))
                }
            }

            if showCopiedToast {
                ToastView(text: NSLocalizedString("Copied", comment: ""))
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle("Address")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentTransaction

struct TransactionStorageDetailView: View {
    let record: PersistentTransaction

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "TXID", value: record.txidHex)
                FieldRow(label: "Direction", value: record.directionName)
                FieldRow(label: "Type", value: record.transactionType)
                FieldRow(label: "Net Amount", value: record.formattedAmount)
                if let fee = record.fee {
                    FieldRow(label: "Fee", value: "\(fee) duffs")
                }
            }
            Section("Block") {
                FieldRow(label: "Context", value: record.contextName)
                FieldRow(label: "Height", value: "\(record.blockHeight)")
                FieldRow(label: "Timestamp", value: "\(record.blockTimestamp)")
                if let hash = record.blockHash {
                    FieldRow(label: "Block Hash", value: hexString(hash))
                }
            }
            Section("Metadata") {
                FieldRow(label: "Label", value: record.label.isEmpty ? "None" : record.label)
                FieldRow(label: "First Seen", value: "\(record.firstSeen)")
                FieldRow(label: "TX Size", value: "\(record.transactionData.count) bytes")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentTxo

struct UtxoStorageDetailView: View {
    let record: PersistentTxo

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Outpoint", value: record.outpointHex)
                FieldRow(label: "TXID", value: record.txidHex)
                FieldRow(label: "Vout", value: "\(record.vout)")
                FieldRow(label: "Amount", value: record.formattedAmount)
                FieldRow(label: "Address", value: record.address)
            }
            Section("Status") {
                FieldRow(label: "Height", value: "\(record.height)")
                FieldRow(label: "Confirmed", value: record.isConfirmed ? "Yes" : "No")
                FieldRow(label: "InstantLocked", value: record.isInstantLocked ? "Yes" : "No")
                FieldRow(label: "Coinbase", value: record.isCoinbase ? "Yes" : "No")
                FieldRow(label: "Locked", value: record.isLocked ? "Yes" : "No")
                FieldRow(label: "Spent", value: record.isSpent ? "Yes" : "No")
            }
            Section("Relationships") {
                FieldRow(label: "Account", value: record.account?.accountTypeName ?? "None")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("UTXO")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentWalletManagerMetadata

struct WalletManagerMetadataStorageDetailView: View {
    let record: PersistentWalletManagerMetadata

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Network", value: record.network.networkName)
                FieldRow(label: "Combined Sync Height", value: "\(record.combinedSyncHeight)")
                FieldRow(label: "Wallet Count", value: "\(record.walletCount)")
                if let hash = record.combinedSyncBlockHash {
                    FieldRow(label: "Block Hash", value: hexString(hash))
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Manager Metadata")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - DashPay family (ported from SwiftExampleApp's storage explorer)

// MARK: - PersistentDPNSName

struct DPNSNameStorageDetailView: View {
    let record: PersistentDPNSName

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Label", value: record.label)
                FieldRow(label: "Normalized Label", value: record.normalizedLabel)
                FieldRow(label: "Parent Domain", value: record.parentDomainName)
                FieldRow(label: "Normalized Parent Domain", value: record.normalizedParentDomainName)
            }
            Section("Status") {
                // `acquiredAt` is Unix-millis from `DpnsNameInfo.acquired_at`;
                // zero when the FFI changeset didn't carry a timestamp.
                FieldRow(label: "Acquired At (ms)", value: record.acquiredAt == 0 ? "—" : "\(record.acquiredAt)")
                if record.acquiredAt > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(record.acquiredAt) / 1000.0)
                    FieldRow(label: "Acquired", value: dateString(date))
                }
            }
            Section("Relationships") {
                NavigationLink(destination: IdentityStorageDetailView(record: record.identity)) {
                    FieldRow(label: "Owner Identity", value: record.identity.identityIdBase58)
                }
                FieldRow(label: "Owner ID (Hex)", value: record.identity.identityIdString)
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("DPNS Name")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDashpayProfile

/// Every stored own-profile field; optional ones render as "—" so partial
/// profiles are obvious rather than fields silently disappearing.
struct DashpayProfileStorageDetailView: View {
    let record: PersistentDashpayProfile

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Display Name", value: record.displayName ?? "—")
                FieldRow(label: "Public Message", value: record.publicMessage ?? "—")
                // Reserved for future DashPay contract revisions; v3 doesn't
                // populate it — surfaced so it isn't invisible if lit up later.
                FieldRow(label: "Bio", value: record.bio ?? "—")
            }
            Section("Avatar") {
                FieldRow(label: "URL", value: record.avatarUrl ?? "—")
                FieldRow(label: "Hash (32 B)", value: record.avatarHash.map { hexString($0) } ?? "—")
                FieldRow(label: "Fingerprint (8 B)", value: record.avatarFingerprint.map { hexString($0) } ?? "—")
            }
            Section("Relationships") {
                NavigationLink(destination: IdentityStorageDetailView(record: record.identity)) {
                    FieldRow(label: "Owner Identity", value: record.identity.identityIdBase58)
                }
                FieldRow(label: "Owner ID (Hex)", value: record.identity.identityIdString)
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("DashPay Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDashpayContactProfile

/// A counterparty's DashPay profile as seen by an owner identity — one
/// row per (owner, contact).
struct DashpayContactProfileStorageDetailView: View {
    let record: PersistentDashpayContactProfile

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Display Name", value: record.displayName ?? "—")
                FieldRow(label: "Public Message", value: record.publicMessage ?? "—")
                FieldRow(label: "Bio", value: record.bio ?? "—")
            }
            Section("Avatar") {
                FieldRow(label: "URL", value: record.avatarUrl ?? "—")
                FieldRow(label: "Hash (32 B)", value: record.avatarHash.map { hexString($0) } ?? "—")
                FieldRow(label: "Fingerprint (8 B)", value: record.avatarFingerprint.map { hexString($0) } ?? "—")
            }
            Section("Relationships") {
                NavigationLink(destination: IdentityStorageDetailView(record: record.owner)) {
                    FieldRow(label: "Owner Identity", value: record.owner.identityIdBase58)
                }
                FieldRow(label: "Owner ID (Hex)", value: hexString(record.ownerIdentityId))
                FieldRow(label: "Contact ID (Hex)", value: hexString(record.contactIdentityId))
            }
            Section("Timestamps") {
                FieldRow(label: "Checked At (ms)", value: String(record.checkedAtMs))
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Contact Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDashpayContactRequest

/// Every payload field plus the relationship pair. The `ownerIdentityId`
/// denorm shadow is redundant with `owner.identityId` but query-friendly.
/// The owner-private alias/note (decrypted contact meta) are included —
/// they back the contacts list titles and the payment-row aliases.
struct DashpayContactRequestStorageDetailView: View {
    let record: PersistentDashpayContactRequest

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Direction", value: record.isOutgoing ? "Outgoing" : "Incoming")
                FieldRow(label: "Sender Key Index", value: "\(record.senderKeyIndex)")
                FieldRow(label: "Recipient Key Index", value: "\(record.recipientKeyIndex)")
                FieldRow(label: "Account Reference", value: "\(record.accountReference)")
                FieldRow(label: "Core Height Created At", value: "\(record.coreHeightCreatedAt)")
                FieldRow(label: "Created At (ms)", value: record.createdAtMillis == 0 ? "—" : "\(record.createdAtMillis)")
            }
            Section("Payload") {
                FieldRow(label: "Encrypted Public Key", value: "\(record.encryptedPublicKey.count) bytes")
                FieldRow(label: "Encrypted Account Label", value: record.encryptedAccountLabel.map { "\($0.count) bytes" } ?? "—")
                FieldRow(label: "Account Label (decrypted)", value: record.contactAccountLabel ?? "—")
                FieldRow(label: "Auto-Accept Proof", value: record.autoAcceptProof.map { "\($0.count) bytes" } ?? "—")
                FieldRow(label: "Alias (owner-private)", value: record.contactAlias ?? "—")
                FieldRow(label: "Note (owner-private)", value: record.contactNote ?? "—")
            }
            Section("Relationships") {
                NavigationLink(destination: IdentityStorageDetailView(record: record.owner)) {
                    FieldRow(label: "Owner Identity", value: record.owner.identityIdBase58)
                }
                FieldRow(label: "Owner ID (Hex, denorm)", value: hexString(record.ownerIdentityId))
                FieldRow(label: "Contact ID (Hex)", value: hexString(record.contactIdentityId))
            }
            Section("Timestamps") {
                if record.createdAtMillis > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(record.createdAtMillis) / 1000.0)
                    FieldRow(label: "Document Created", value: dateString(date))
                }
                FieldRow(label: "Row Created", value: dateString(record.createdAt))
                FieldRow(label: "Row Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Contact Request")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDashpayPayment

struct DashpayPaymentStorageDetailView: View {
    let record: PersistentDashpayPayment

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Direction", value: record.direction == .sent ? "Sent" : "Received")
                FieldRow(label: "Status", value: statusText)
                FieldRow(label: "Amount", value: String(format: "%.8f DASH", Double(record.amountDuffs) / 100_000_000))
                FieldRow(label: "Amount (duffs)", value: "\(record.amountDuffs)")
                FieldRow(label: "Memo", value: record.memo ?? "—")
            }
            Section("Transaction") {
                FieldRow(label: "Txid", value: record.txid)
            }
            Section("Identities") {
                FieldRow(label: "Owner", value: hexString(record.ownerIdentityId))
                FieldRow(label: "Counterparty", value: hexString(record.counterpartyIdentityId))
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("DashPay Payment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch record.status {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - PersistentInvitation

/// Human label for a `PersistentInvitation.statusRaw` discriminant
/// (0 = Created, 1 = Claimed, 2 = Reclaimed). Shared with the list view;
/// an unmapped value renders as "Unknown (n)" rather than being hidden.
func invitationStatusLabel(_ raw: Int) -> String {
    switch raw {
    case 0: return "Created"
    case 1: return "Claimed"
    case 2: return "Reclaimed"
    default: return "Unknown (\(raw))"
    }
}

/// One created DashPay invitation (DIP-13). No secret column — the
/// one-time voucher key is never stored.
struct InvitationStorageDetailView: View {
    let record: PersistentInvitation

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Status", value: invitationStatusLabel(record.statusRaw))
                FieldRow(label: "Amount", value: String(format: "%.8f DASH", Double(record.amountDuffs) / 100_000_000))
                FieldRow(label: "Amount (duffs)", value: "\(record.amountDuffs)")
                FieldRow(label: "Funding index", value: "\(record.fundingIndexRaw)")
                FieldRow(label: "Has inviter", value: record.hasInviter ? "Yes" : "No")
            }
            Section("Outpoint") {
                FieldRow(label: "Outpoint", value: record.outPointHex)
                FieldRow(label: "Raw outpoint", value: hexString(record.rawOutPoint))
            }
            Section("Wallet") {
                FieldRow(label: "Wallet id", value: hexString(record.walletId))
            }
            Section("Timestamps") {
                FieldRow(label: "Expiry (unix)", value: "\(record.expiryUnix)")
                FieldRow(label: "Created (unix)", value: "\(record.createdAtSecs)")
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.updatedAt))
            }
        }
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentDashpayIgnoredSender

/// One DashPay ignored sender (per-sender mute, local-only).
struct DashpayIgnoredSenderStorageDetailView: View {
    let record: PersistentDashpayIgnoredSender

    var body: some View {
        Form {
            Section("Suppression key") {
                FieldRow(label: "Owner", value: hexString(record.ownerIdentityId))
                FieldRow(label: "Ignored sender", value: hexString(record.ignoredSenderId))
            }
            Section("Audit") {
                FieldRow(label: "Ignored", value: dateString(record.ignoredAt))
            }
        }
        .navigationTitle("Ignored Sender")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Asset locks / pending inputs / masternodes / shielded family
// (ported from SwiftExampleApp's storage explorer)

// MARK: - PersistentPendingInput

struct PendingInputStorageDetailView: View {
    let record: PersistentPendingInput

    var body: some View {
        Form {
            Section("Core") {
                FieldRow(label: "Outpoint", value: outpointHex(record.outpoint))
                FieldRow(label: "Input Index", value: "\(record.inputIndex)")
                // Display order matches the canonical block-explorer form
                // (byte-reversed from on-disk wire order).
                FieldRow(
                    label: "Spending TXID",
                    value: record.spendingTxid.reversed().map { String(format: "%02x", $0) }.joined())
                FieldRow(label: "Wallet ID", value: record.walletId.isEmpty ? "—" : hexString(record.walletId))
            }
            Section("Relationships") {
                if let spending = record.spendingTransaction {
                    NavigationLink(destination: TransactionStorageDetailView(record: spending)) {
                        FieldRow(label: "Spending Transaction", value: spending.txidHex)
                    }
                } else {
                    // The parent transaction may not have faulted in (the
                    // cascade-delete relationship keeps them in lockstep,
                    // but the field is optional for SwiftData's
                    // brief-window tolerance) — surface the orphan.
                    FieldRow(label: "Spending Transaction", value: "— (unlinked)")
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
            }
            Section {
                Text(
                    "A pending input lives here until its previous-output "
                    + "PersistentTxo arrives. On `upsertUtxo`, the matching "
                    + "row is consumed: the new TXO is marked spent, linked "
                    + "to this row's spendingTransaction, and the pending "
                    + "entry is deleted in one pass.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Pending Input")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 36-byte outpoint as `<txid hex (display order)>:<vout>`.
    private func outpointHex(_ outpoint: Data) -> String {
        guard outpoint.count == 36 else {
            return outpoint.map { String(format: "%02x", $0) }.joined()
        }
        let txid = outpoint.prefix(32)
        let voutBytes = outpoint.suffix(4)
        let vout = voutBytes.withUnsafeBytes { raw in
            raw.load(as: UInt32.self).littleEndian
        }
        let txidHex = txid.reversed().map { String(format: "%02x", $0) }.joined()
        return "\(txidHex):\(vout)"
    }
}

// MARK: - PersistentMasternode

struct MasternodeStorageDetailView: View {
    let record: PersistentMasternode

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "proTxHash", value: record.proTxHashHex)
                FieldRow(label: "Registration Txid", value: hexString(record.registrationTxid))
                FieldRow(label: "Type", value: record.typeName)
                FieldRow(label: "Status", value: record.statusName)
            }
            Section("Service") {
                FieldRow(label: "Service Address", value: record.serviceAddress ?? "—")
            }
            Section("Keys") {
                FieldRow(label: "Owner Key Hash", value: record.ownerKeyHash.map(hexString) ?? "—")
                FieldRow(label: "Voting Key Hash", value: record.votingKeyHash.map(hexString) ?? "—")
                FieldRow(label: "Owner Address", value: record.ownerAddress ?? "—")
                FieldRow(label: "Voting Address", value: record.votingAddress ?? "—")
            }
            Section("Collateral") {
                FieldRow(label: "Collateral Txid", value: record.collateralTxid.map(hexString) ?? "—")
                FieldRow(label: "Collateral Vout", value: "\(record.collateralVout)")
            }
            Section("Aggregation") {
                FieldRow(label: "Has Registration", value: record.hasRegistration ? "Yes" : "No")
                FieldRow(label: "Registration Height", value: "\(record.registrationHeight)")
                FieldRow(label: "Tx Count", value: "\(record.txCount)")
                FieldRow(label: "Order Index", value: "\(record.orderIndex)")
                FieldRow(label: "Type Index", value: "\(record.typeIndex)")
            }
            Section("Revocation") {
                FieldRow(label: "Revoked", value: record.revoked ? "Yes" : "No")
                FieldRow(label: "Revocation Reason", value: "\(record.revocationReason)")
                FieldRow(label: "Status Raw", value: "\(record.statusRaw)")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle(record.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentAssetLock

/// Human-readable label for `PersistentAssetLock.statusRaw` — one home
/// for the 0…4 mapping (mirrors the Rust-side `AssetLockStatus` enum and
/// the example app's `PersistentAssetLockDisplay`).
extension PersistentAssetLock {
    var statusLabel: String {
        switch statusRaw {
        case 0: return "Built"
        case 1: return "Broadcast"
        case 2: return "InstantSendLocked"
        case 3: return "ChainLocked"
        case 4: return "Consumed"
        default: return "Unknown(\(statusRaw))"
        }
    }
}

struct AssetLockStorageDetailView: View {
    let record: PersistentAssetLock

    /// Candidate identity rows at this asset lock's `identityIndex`.
    /// Filtered down to the strict `(walletId, identityIndex)` match in
    /// `linkedIdentity` — the predicate alone would miss legacy rows
    /// whose `wallet` relationship isn't populated.
    @Query private var candidateIdentities: [PersistentIdentity]

    init(record: PersistentAssetLock) {
        self.record = record
        // `identityIndexRaw` is `Int32` (changeset FFI) but
        // `PersistentIdentity.identityIndex` is `UInt32` (DIP-9 slot).
        // Bridge outside the closure — `#Predicate` disallows inline
        // conversions.
        let identityIndex = UInt32(bitPattern: record.identityIndexRaw)
        _candidateIdentities = Query(
            filter: #Predicate<PersistentIdentity> { identity in
                identity.identityIndex == identityIndex
            })
    }

    /// The identity row this asset lock points at: strict
    /// `(walletId, identityIndex)` match preferred; a SINGLE orphaned
    /// candidate (no wallet relationship) is accepted, multiple are
    /// ambiguous and we don't guess.
    private var linkedIdentity: PersistentIdentity? {
        if let strict = candidateIdentities.first(where: { $0.wallet?.walletId == record.walletId }) {
            return strict
        }
        let orphaned = candidateIdentities.filter { $0.wallet == nil }
        return orphaned.count == 1 ? orphaned.first : nil
    }

    var body: some View {
        Form {
            Section("Asset Lock") {
                FieldRow(label: "Outpoint", value: record.outPointHex)
                FieldRow(label: "Status", value: record.statusLabel)
                FieldRow(label: "Funding Type", value: fundingTypeLabel(record.fundingTypeRaw))
                FieldRow(label: "Identity Index", value: "\(record.identityIndexRaw)")
                FieldRow(label: "Amount (duffs)", value: "\(record.amountDuffs)")
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
            }
            if isAddressFunding {
                // Recipient platform address, stamped by Swift after a
                // successful `fundFromAssetLock`. `nil` on rows predating
                // the column or whose funding hasn't completed.
                Section("Recipient Platform Address") {
                    if let hash = record.recipientPlatformAddressHash {
                        FieldRow(label: "Hash", value: hexString(hash))
                        FieldRow(label: "Address Type", value: addressTypeLabel(record.recipientPlatformAddressType))
                        if let encoded = bech32mPlatformAddress(
                            hash: hash,
                            addressType: record.recipientPlatformAddressType) {
                            FieldRow(label: "Bech32m", value: encoded)
                        }
                    } else if record.statusRaw == 4 {
                        FieldRow(label: "Recipient", value: "— (pre-this-commit row)")
                    } else {
                        FieldRow(label: "Recipient", value: "— (funding not yet completed)")
                    }
                }
            }
            if isIdentityFunding {
                Section("Identity") {
                    if let identity = linkedIdentity {
                        // Static row, deliberately no navigation — pushing
                        // the identity detail from this nested path hung
                        // the main thread on iOS 26 in the example app.
                        Text(identity.identityIdBase58)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } else {
                        // No identity row yet: pre-finality, or IS/CL-locked
                        // with the IdentityCreate never completed.
                        FieldRow(label: pendingLabel(record.statusRaw), value: record.statusLabel)
                    }
                }
            }
            Section("Bytes") {
                FieldRow(label: "Transaction Bytes", value: "\(record.transactionBytes.count) bytes")
                FieldRow(label: "Proof Bytes", value: record.proofBytes.map { "\($0.count) bytes" } ?? "—")
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.updatedAt))
            }
        }
        .navigationTitle("Asset Lock")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fundingTypeLabel(_ raw: Int) -> String {
        switch raw {
        case 0: return "IdentityRegistration"
        case 1: return "IdentityTopUp"
        case 2: return "IdentityTopUpNotBound"
        case 3: return "IdentityInvitation"
        case 4: return "AssetLockAddressTopUp"
        case 5: return "AssetLockShieldedAddressTopUp"
        default: return "Unknown(\(raw))"
        }
    }

    /// Registration / top-up — the funding types that resolve to a
    /// single identity slot on this wallet.
    private var isIdentityFunding: Bool {
        record.fundingTypeRaw == 0 || record.fundingTypeRaw == 1
    }

    /// `AddressFundingFromAssetLockTransition` (type 4).
    private var isAddressFunding: Bool {
        record.fundingTypeRaw == 4
    }

    private func addressTypeLabel(_ raw: UInt8?) -> String {
        switch raw {
        case 0: return "P2PKH"
        case 1: return "P2SH"
        case .some(let v): return "Unknown(\(v))"
        case .none: return "—"
        }
    }

    /// DIP-0018 bech32m encoding of the recipient hash, via the app's
    /// shared `Bech32m` (the example app carries its own encoder; we
    /// don't need to). Wire type byte: 0xb0 P2PKH / 0x80 P2SH — distinct
    /// from the storage discriminant (0 / 1).
    private func bech32mPlatformAddress(hash: Data, addressType: UInt8?) -> String? {
        guard hash.count == 20 else { return nil }
        let typeByte: UInt8
        switch addressType {
        case 0: typeByte = 0xb0
        case 1: typeByte = 0x80
        default: return nil
        }
        let hrp = Bech32m.platformHrp(mainnet: !WalletEnvironment.isTestnet)
        return Bech32m.encode(hrp: hrp, data: Data([typeByte]) + hash)
    }

    /// Label when no identity row exists for this slot yet: mid-flight
    /// vs locked-but-unconsumed.
    private func pendingLabel(_ raw: Int) -> String {
        switch raw {
        case 0, 1: return "In progress"
        case 2, 3: return "Pending (unused)"
        default: return "Pending"
        }
    }
}

// MARK: - PersistentShieldedNote

struct ShieldedNoteStorageDetailView: View {
    let record: PersistentShieldedNote

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
                FieldRow(label: "Position", value: "\(record.position)")
            }
            Section("Commitment") {
                FieldRow(label: "cmx", value: hexString(record.cmx))
                FieldRow(label: "Nullifier", value: hexString(record.nullifier))
            }
            Section("State") {
                FieldRow(label: "Block Height", value: "\(record.blockHeight)")
                FieldRow(label: "Spent", value: record.isSpent ? "Yes" : "No")
                FieldRow(label: "Value", value: "\(record.value) credits")
            }
            Section("Note Bytes") {
                Text(hexString(record.noteData))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Shielded Note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentShieldedOutgoingNote

struct ShieldedOutgoingNoteStorageDetailView: View {
    let record: PersistentShieldedOutgoingNote

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
            }
            Section("Commitment") {
                FieldRow(label: "cmx", value: hexString(record.cmx))
            }
            Section("Send") {
                FieldRow(label: "Recipient", value: hexString(record.recipient))
                FieldRow(label: "Value", value: "\(record.value) credits")
                FieldRow(label: "Block Height", value: "\(record.blockHeight)")
            }
            Section("Memo") {
                if record.memo.isEmpty {
                    Text("(empty)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(hexString(record.memo))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Shielded Sent Note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentShieldedActivity

struct ShieldedActivityStorageDetailView: View {
    let record: PersistentShieldedActivity

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
                FieldRow(label: "Entry ID", value: hexString(record.entryId))
            }
            Section("Classification") {
                FieldRow(label: "Kind Tag", value: kindDisplay(record.kindTag))
                FieldRow(label: "Direction", value: directionDisplay(record.direction))
                FieldRow(label: "Status", value: statusDisplay(record.status))
            }
            Section("Amounts") {
                FieldRow(label: "Amount", value: "\(record.amount) credits")
                FieldRow(label: "Fee", value: record.hasFee ? "\(record.fee) credits" : "(unknown)")
                FieldRow(label: "Block Height", value: record.hasBlockHeight ? "\(record.blockHeight)" : "(pending)")
            }
            Section("Linkage") {
                if !record.identityId.isEmpty {
                    FieldRow(label: "Identity ID", value: hexString(record.identityId))
                }
                if !record.counterparty.isEmpty {
                    FieldRow(label: "Counterparty", value: hexString(record.counterparty))
                }
                FieldRow(label: "Note cmxs", value: "\(record.noteCmxs.count / 32)")
                FieldRow(label: "Spent Nullifiers", value: "\(record.spentNullifiers.count / 32)")
            }
            Section("Memo") {
                if record.memo.isEmpty {
                    Text("(empty)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(hexString(record.memo))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section("Timestamps") {
                FieldRow(label: "Created (ms)", value: "\(record.createdAtMs)")
                FieldRow(label: "Created", value: dateString(record.createdAt))
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Shielded Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindDisplay(_ tag: Int) -> String {
        let name: String
        switch tag {
        case 0: name = "Shield"
        case 1: name = "ShieldFromAssetLock"
        case 2: name = "Received"
        case 3: name = "Sent"
        case 4: name = "Unshield"
        case 5: name = "Withdrawal"
        case 6: name = "IdentityCreate"
        case 7: name = "ShieldedSpend"
        default: return "Unknown(\(tag))"
        }
        return "\(name) (\(tag))"
    }

    private func directionDisplay(_ raw: Int) -> String {
        let name: String
        switch raw {
        case 0: name = "In"
        case 1: name = "Out"
        case 2: name = "Self"
        default: return "Unknown(\(raw))"
        }
        return "\(name) (\(raw))"
    }

    private func statusDisplay(_ raw: Int) -> String {
        let name: String
        switch raw {
        case 0: name = "Pending"
        case 1: name = "Confirmed"
        case 2: name = "Failed"
        default: return "Unknown(\(raw))"
        }
        return "\(name) (\(raw))"
    }
}

// MARK: - PersistentShieldedSyncState

struct ShieldedSyncStateStorageDetailView: View {
    let record: PersistentShieldedSyncState

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
            }
            Section("Sync") {
                FieldRow(label: "Last Synced Index", value: "\(record.lastSyncedIndex)")
            }
            Section("Timestamps") {
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Shielded Sync State")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PersistentShieldedViewingKey

struct ShieldedViewingKeyStorageDetailView: View {
    let record: PersistentShieldedViewingKey

    var body: some View {
        Form {
            Section("Identity") {
                FieldRow(label: "Wallet ID", value: hexString(record.walletId))
                FieldRow(label: "Account Index", value: "\(record.accountIndex)")
            }
            Section("Viewing Key") {
                // Viewing-grade only (cannot spend), but still key material —
                // the full FVK is intentionally rendered for QA inspection,
                // matching how the explorer shows other derived key batches.
                FieldRow(label: "FVK Length", value: "\(record.fvkBytes.count) bytes")
                FieldRow(label: "FVK (hex)", value: hexString(record.fvkBytes))
            }
            Section("Timestamps") {
                FieldRow(label: "Updated", value: dateString(record.lastUpdated))
            }
        }
        .navigationTitle("Shielded Viewing Key")
        .navigationBarTitleDisplayMode(.inline)
    }
}
