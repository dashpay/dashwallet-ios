import Foundation
import Combine

class CTXSpendService: CTXSpendAPIAccessTokenProvider, ObservableObject {
    public static let shared: CTXSpendService = .init()
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let accessToken = "ctx_spend_access_token"
        static let refreshToken = "ctx_spend_refresh_token"
        static let email = "ctx_spend_email"
        static let deviceUUID = "ctx_spend_device_uuid"
    }
    
    var accessToken: String? {
        return KeychainService.load(key: Keys.accessToken)
    }
    
    var userEmail: String? {
        KeychainService.load(key: Keys.email)
    }
    
    @Published private(set) var isUserSignedIn = false
    
    init() {
        CTXSpendAPI.initialize(with: self)
        updateSignInState()
    }
    
    private func updateSignInState() {
        let token = accessToken
        isUserSignedIn = token != nil && !token!.isEmpty
    }
    
    func signIn(email: String) async throws -> Bool {
        do {
            try await CTXSpendAPI.shared.request(.login(email: email))
            KeychainService.save(key: Keys.email, data: email)
            
            if userDefaults.string(forKey: Keys.deviceUUID) == nil {
                userDefaults.set(UUID().uuidString, forKey: Keys.deviceUUID)
            }
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func verifyEmail(code: String) async throws -> Bool {
        guard let email = userEmail else {
            DSLogger.log("CTX: email is missing while trying to verify")
            throw CTXSpendError.unknown
        }
        
        do {
            let response: VerifyEmailResponse = try await CTXSpendAPI.shared.request(.verifyEmail(email: email, code: code))
            
            KeychainService.save(key: Keys.accessToken, data: response.accessToken)
            KeychainService.save(key: Keys.refreshToken, data: response.refreshToken)
            updateSignInState()
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func logout() {
        KeychainService.delete(key: Keys.accessToken)
        KeychainService.delete(key: Keys.refreshToken)
        KeychainService.delete(key: Keys.email)
        userDefaults.removeObject(forKey: Keys.deviceUUID)
        updateSignInState()
    }
    
    // MARK: - Gift Card Methods
    
    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String = "USD", cryptoCurrency: String = "DASH") async throws -> GiftCardResponse {
        let request = PurchaseGiftCardRequest(
            cryptoCurrency: cryptoCurrency,
            fiatCurrency: fiatCurrency,
            fiatAmount: fiatAmount,
            merchantId: merchantId
        )
        
        do {
            return try await CTXSpendAPI.shared.request(.purchaseGiftCard(request))
        } catch {
            throw mapError(error)
        }
    }
    
    func getMerchant(merchantId: String) async throws -> MerchantResponse {
        do {
            return try await CTXSpendAPI.shared.request(.getMerchant(merchantId))
        } catch {
            throw mapError(error)
        }
    }
    
    func getGiftCardByTxid(txid: String) async throws -> GiftCardResponse {
        do {
            return try await CTXSpendAPI.shared.request(.getGiftCard(txid))
        } catch {
            throw mapError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapError(_ error: Error) -> Error {
        if let ctxError = error as? CTXSpendError {
            return ctxError
        }
        
        return CTXSpendError.networkError
    }
}

// MARK: - KeychainService

public class KeychainService {
    static func save(key: String, data: String) {
        if let dataToStore = data.data(using: .utf8) {
            let query = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: dataToStore
            ] as [String: Any]
            
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    static func load(key: String) -> String? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == noErr {
            if let data = result as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        
        return nil
    }
    
    static func delete(key: String) {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as [String: Any]
        
        SecItemDelete(query as CFDictionary)
    }
} 
