import Foundation
import SwiftDashSDK

/// Friendship status between current identity and another identity
@objc enum DWPlatformFriendshipStatus: Int {
    case none = 0
    case outgoing = 1
    case incoming = 2
    case friends = 3
}

/// Registration step tracking
@objc enum DWPlatformRegistrationStep: Int {
    case none = 0
    case fundingTransaction = 1
    case identityRegistered = 2
    case usernameRegistered = 3
    case profileCreated = 4
    case complete = 5
}

/// Represents a platform user for display in UI
@objc class DWPlatformUser: NSObject {
    @objc let username: String
    @objc let identityId: Data
    @objc let displayName: String?
    @objc let avatarURL: String?
    @objc let publicMessage: String?

    init(username: String, identityId: Data, displayName: String? = nil,
         avatarURL: String? = nil, publicMessage: String? = nil) {
        self.username = username
        self.identityId = identityId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.publicMessage = publicMessage
        super.init()
    }
}

/// Central service that wraps SwiftDashSDK for use in dashwallet-ios.
/// Bridges Swift async APIs to ObjC-compatible completion handlers.
@objc class PlatformService: NSObject {

    // MARK: - Singleton

    @objc static let shared = PlatformService()

    // MARK: - SDK Components

    private var sdk: SDK?
    private var dashPayService: DashPayService
    private var platformWallet: PlatformWallet?
    private var currentNetwork: AppNetwork = .testnet

    // MARK: - State

    @objc private(set) var isInitialized: Bool = false
    @objc private(set) var isRegistered: Bool = false
    @objc private(set) var currentUsername: String?

    // MARK: - Init

    private override init() {
        self.dashPayService = DashPayService()
        super.init()
    }

    // MARK: - Initialization

    /// Initialize the platform SDK with mnemonic and network
    @objc func initialize(mnemonic: String, isTestnet: Bool, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                // Initialize SDK
                SDK.initialize()
                let network: AppNetwork = isTestnet ? .testnet : .mainnet
                self.currentNetwork = network
                let sdkInstance = try SDK(network: network.sdkNetwork)
                self.sdk = sdkInstance

                // Initialize DashPay service with wallet
                let platformNetwork: PlatformNetwork = isTestnet ? .testnet : .mainnet
                try self.dashPayService.initializeWallet(mnemonic: mnemonic, network: platformNetwork)

                self.isInitialized = true

                // Check if we have an existing identity
                if let identity = try self.dashPayService.getPrimaryIdentity() {
                    self.isRegistered = true
                    self.currentUsername = try? identity.getLabel()
                }

                await MainActor.run {
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    completion(false, error)
                }
            }
        }
    }

    /// Shutdown and cleanup
    @objc func shutdown() {
        sdk = nil
        isInitialized = false
        isRegistered = false
        currentUsername = nil
    }

    // MARK: - Identity Operations

    /// Get identity balance in credits
    @objc func getIdentityBalance(identityId: Data, completion: @escaping (UInt64, Error?) -> Void) {
        guard let sdk = sdk else {
            completion(0, DashPayError.noWallet)
            return
        }
        Task {
            do {
                let balance = try sdk.identities.getBalance(id: identityId)
                await MainActor.run { completion(balance, nil) }
            } catch {
                await MainActor.run { completion(0, error) }
            }
        }
    }

    /// Fetch the current user's identity
    @objc func getCurrentIdentity(completion: @escaping (DWPlatformUser?, Error?) -> Void) {
        Task {
            do {
                guard let identity = try dashPayService.getPrimaryIdentity() else {
                    await MainActor.run { completion(nil, nil) }
                    return
                }
                let id = try identity.getId()
                let label = try? identity.getLabel()
                let user = DWPlatformUser(
                    username: label ?? "",
                    identityId: id
                )
                await MainActor.run { completion(user, nil) }
            } catch {
                await MainActor.run { completion(nil, error) }
            }
        }
    }

    // MARK: - Contact Request Operations

    /// Fetch all contact requests (incoming + outgoing + established)
    @objc func fetchContactRequests(completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                guard let identity = try dashPayService.getPrimaryIdentity() else {
                    await MainActor.run { completion(false, DashPayError.noCurrentIdentity) }
                    return
                }
                // Fetch all request types
                _ = try dashPayService.getIncomingContactRequests(identity: identity)
                _ = try dashPayService.getSentContactRequests(identity: identity)
                _ = try dashPayService.getEstablishedContacts(identity: identity)

                await MainActor.run {
                    NotificationCenter.default.post(name: .dwDashPayContactsDidUpdate, object: nil)
                    completion(true, nil)
                }
            } catch {
                await MainActor.run { completion(false, error) }
            }
        }
    }

    /// Accept a contact request from a sender
    @objc func acceptContactRequest(senderId: Data, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                guard let identity = try dashPayService.getPrimaryIdentity() else {
                    await MainActor.run { completion(false, DashPayError.noCurrentIdentity) }
                    return
                }
                try dashPayService.acceptContactRequest(identity: identity, from: senderId)
                await MainActor.run { completion(true, nil) }
            } catch {
                await MainActor.run { completion(false, error) }
            }
        }
    }

    /// Send a contact request to a recipient
    @objc func sendContactRequest(recipientId: Data, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                guard let identity = try dashPayService.getPrimaryIdentity() else {
                    await MainActor.run { completion(false, DashPayError.noCurrentIdentity) }
                    return
                }
                // For now use empty encrypted key - will be derived properly
                try dashPayService.sendContactRequest(
                    from: identity,
                    to: recipientId,
                    encryptedPublicKey: Data()
                )
                await MainActor.run { completion(true, nil) }
            } catch {
                await MainActor.run { completion(false, error) }
            }
        }
    }

    /// Get friendship status with another identity
    @objc func friendshipStatus(with identityId: Data) -> DWPlatformFriendshipStatus {
        guard let identity = try? dashPayService.getPrimaryIdentity() else {
            return .none
        }

        let isEstablished = (try? dashPayService.isContactEstablished(identity: identity, contactId: identityId)) ?? false
        if isEstablished {
            return .friends
        }

        let hasSent = (try? identity.getSentContactRequest(recipientId: identityId)) != nil
        if hasSent {
            return .outgoing
        }

        let hasIncoming = (try? identity.getIncomingContactRequest(senderId: identityId)) != nil
        if hasIncoming {
            return .incoming
        }

        return .none
    }

    // MARK: - User Search

    /// Search for users by username prefix
    @objc func searchUsers(prefix: String, completion: @escaping ([DWPlatformUser], Error?) -> Void) {
        guard let sdk = sdk else {
            completion([], DashPayError.noWallet)
            return
        }
        Task {
            do {
                // Query DPNS documents for username prefix match
                // This uses the SDK's identity search capabilities
                // TODO: Implement DPNS document query when SDK exposes document search
                // For now, try fetching by exact name
                if let identity = try sdk.identities.get(id: prefix) {
                    let user = DWPlatformUser(
                        username: prefix,
                        identityId: Data() // TODO: get identity id bytes
                    )
                    await MainActor.run { completion([user], nil) }
                } else {
                    await MainActor.run { completion([], nil) }
                }
            } catch {
                await MainActor.run { completion([], error) }
            }
        }
    }

    // MARK: - Username Registration

    /// Register a username on the platform
    @objc func registerUsername(_ username: String,
                                stepCompletion: @escaping (DWPlatformRegistrationStep) -> Void,
                                completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                guard isInitialized else {
                    await MainActor.run { completion(false, DashPayError.noWallet) }
                    return
                }

                // Step 1: Identity should already exist or be created
                await MainActor.run { stepCompletion(.identityRegistered) }

                // Step 2: Register DPNS username via state transition
                // TODO: Implement DPNS registration through SDK
                await MainActor.run { stepCompletion(.usernameRegistered) }

                self.currentUsername = username
                self.isRegistered = true

                await MainActor.run {
                    stepCompletion(.complete)
                    completion(true, nil)
                }
            } catch {
                await MainActor.run { completion(false, error) }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let dwDashPayContactsDidUpdate = Notification.Name("DWDashPayContactsDidUpdateNotification")
}
