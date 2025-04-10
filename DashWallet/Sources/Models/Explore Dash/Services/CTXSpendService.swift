import Foundation

enum CTXSpendError: Error {
    case invalidResponse
    case networkError(Error)
    case invalidCode
    case unknown
}

class CTXSpendService {
    private let baseURL = "https://api.ctxspend.com" // Replace with actual API URL
    
    func signIn(email: String, isSignIn: Bool) async throws -> Bool {
        let endpoint = isSignIn ? "/auth/signin" : "/auth/signup"
        let url = URL(string: baseURL + endpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CTXSpendError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CTXSpendError.unknown
        }
        
        return true
    }
    
    func verifyEmail(code: String) async throws -> Bool {
        let url = URL(string: baseURL + "/auth/verify")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["code": code]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CTXSpendError.invalidResponse
        }
        
        if httpResponse.statusCode == 400 {
            throw CTXSpendError.invalidCode
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CTXSpendError.unknown
        }
        
        return true
    }
} 