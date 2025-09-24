# External Integrations Guide

This document provides comprehensive information about external service integrations, third-party dependencies, and API integration patterns used in the Dash Wallet iOS project.

## Core External Services

### DashSync Integration
**Location**: Local dependency at `../DashSync/`
**Purpose**: Core Dash protocol implementation and SPV functionality

**Key Integration Points:**
- `DWEnvironment` provides access to current wallet and chain instances
- Transaction broadcasting and validation
- Blockchain synchronization and block header management
- Private key and address generation
- InstantSend and ChainLocks support

**Usage Pattern:**
```objc
DSChain *chain = [DWEnvironment sharedInstance].currentChain;
DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

// Create transaction
DSTransaction *transaction = [wallet transactionForAmounts:amounts
                                              toAddresses:addresses
                                               withFeePerB:feePerByte];
```

### Firebase Services
**Dependencies**: `Firebase/DynamicLinks`, `FirebaseStorage`
**Configuration**: `GoogleService-Info.plist`

**Dynamic Links Integration:**
```swift
// Handle incoming dynamic links
func application(_ app: UIApplication, 
                open url: URL, 
                options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    
    if let dynamicLink = DynamicLinks.dynamicLinks().dynamicLink(fromCustomSchemeURL: url) {
        handleDynamicLink(dynamicLink)
        return true
    }
    
    return false
}
```

**Storage Integration:**
- Profile image storage for DashPay
- Backup data synchronization
- Asset caching for performance

## Financial Service Integrations

### Coinbase Integration
**Files**: `DashWallet/Sources/Models/Coinbase/`
**Pattern**: OAuth 2.0 + REST API with async/await

**Authentication Flow:**
```swift
class CoinbaseAuth {
    func authenticate() async throws -> CoinbaseToken {
        // 1. Redirect to Coinbase OAuth
        let authURL = buildAuthURL()
        await presentWebAuth(authURL)
        
        // 2. Exchange code for token
        let token = try await exchangeCodeForToken(authCode)
        
        // 3. Store securely
        try await tokenStorage.store(token)
        
        return token
    }
}
```

**API Integration:**
```swift
class CoinbaseService: HTTPClientBasedService {
    func getAccounts() async throws -> [CoinbaseAccount] {
        let endpoint = CoinbaseEndpoint.accounts
        return try await httpClient.request(endpoint)
    }
    
    func createBuyOrder(amount: Decimal, currency: String) async throws -> BuyOrder {
        let request = CreateBuyOrderRequest(amount: amount, currency: currency)
        return try await httpClient.post(.buyOrders, body: request)
    }
}
```

### Uphold Integration
**Files**: `DashWallet/Sources/Models/Uphold/`
**Pattern**: OAuth 2.0 + REST API with delegate callbacks

**Legacy Integration Pattern:**
```objc
@interface DWUpholdClient : NSObject
- (void)authenticateWithCompletion:(void (^)(NSError *error))completion;
- (void)getCardsWithCompletion:(void (^)(NSArray<DWUpholdCardObject *> *cards, NSError *error))completion;
- (void)createTransactionFromCard:(NSString *)cardId 
                         toAmount:(NSString *)amount
                       completion:(void (^)(DWUpholdTransactionObject *transaction, NSError *error))completion;
@end
```

**Modern Swift Wrapper:**
```swift
extension UpholdClient {
    func authenticate() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            authenticateWithCompletion { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
```

### CrowdNode Staking Integration
**Files**: `DashWallet/Sources/Models/CrowdNode/`
**Pattern**: Transaction-based API with web interface

**API Integration:**
```swift
class CrowdNodeWebService {
    func createAccount(email: String) async throws -> CrowdNodeAccount {
        let endpoint = CrowdNodeEndpoint.createAccount
        let request = CreateAccountRequest(email: email)
        return try await httpClient.post(endpoint, body: request)
    }
    
    func getStakingInfo() async throws -> StakingInfo {
        return try await httpClient.get(.stakingInfo)
    }
}
```

**Transaction Monitoring:**
```swift
class TransactionObserver {
    func observeTransactions() {
        NotificationCenter.default.addObserver(
            forName: .DSWalletBalanceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleBalanceChange(notification)
        }
    }
    
    private func handleBalanceChange(_ notification: Notification) {
        // Check for CrowdNode-related transactions
        if let crowdNodeTx = identifyCrowdNodeTransaction() {
            updateStakingStatus(crowdNodeTx)
        }
    }
}
```

## Third-Party Libraries

### Networking Stack
**Primary**: `Moya` for type-safe networking
**Configuration**: Generic HTTP client wrapper

**Implementation Pattern:**
```swift
enum APIEndpoint {
    case getAccount(id: String)
    case createTransaction(request: TransactionRequest)
}

extension APIEndpoint: TargetType {
    var baseURL: URL {
        return URL(string: "https://api.example.com")!
    }
    
    var path: String {
        switch self {
        case .getAccount(let id):
            return "/accounts/\(id)"
        case .createTransaction:
            return "/transactions"
        }
    }
    
    var method: Moya.Method {
        switch self {
        case .getAccount:
            return .get
        case .createTransaction:
            return .post
        }
    }
}
```

**Generic HTTP Client:**
```swift
class HTTPClient<ResponseType: Codable> {
    private let provider: MoyaProvider<APIEndpoint>
    
    func request<T: Codable>(_ endpoint: APIEndpoint) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(endpoint) { result in
                switch result {
                case .success(let response):
                    do {
                        let decodedResponse = try JSONDecoder().decode(T.self, from: response.data)
                        continuation.resume(returning: decodedResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### Image Processing
**Libraries**: `SDWebImage`, `SDWebImageSwiftUI`, `TOCropViewController`, `CocoaImageHashing`

**SDWebImage Integration:**
```swift
import SDWebImage

extension UIImageView {
    func setImageFromURL(_ urlString: String?, placeholder: UIImage? = nil) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            image = placeholder
            return
        }
        
        sd_setImage(with: url, 
                   placeholderImage: placeholder,
                   options: [.retryFailed, .scaleDownLargeImages])
    }
}
```

**Image Cropping Integration:**
```swift
func presentImageCropViewController(image: UIImage) {
    let cropViewController = TOCropViewController(croppingStyle: .circular, image: image)
    cropViewController.delegate = self
    
    present(cropViewController, animated: true)
}

extension ViewController: TOCropViewControllerDelegate {
    func cropViewController(_ cropViewController: TOCropViewController, 
                           didCropTo image: UIImage, 
                           with cropRect: CGRect, 
                           angle: Int) {
        // Handle cropped image
        updateProfileImage(image)
        cropViewController.dismiss(animated: true)
    }
}
```

### Database and Storage
**Primary**: `SQLite.swift` with custom migration manager
**Migration**: `SQLiteMigrationManager.swift`

**Database Setup:**
```swift
class DatabaseConnection {
    private var db: Connection?
    
    func connect() throws {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let dbPath = documentsPath + "/DashWallet.sqlite"
        
        db = try Connection(dbPath)
        try migrateIfNeeded()
    }
    
    private func migrateIfNeeded() throws {
        guard let migrationsBundle = Bundle.main.url(forResource: "Migrations", withExtension: "bundle"),
              let bundle = Bundle(url: migrationsBundle) else {
            throw DatabaseError.migrationsNotFound
        }
        
        let migrationManager = SQLiteMigrationManager(db: db!, migrationsBundle: bundle)
        try migrationManager.migrateDatabase()
    }
}
```

### Authentication and Security
**Libraries**: `SwiftJWT`, `BlueCryptor`, `BlueECC`, `BlueRSA`

**JWT Token Handling:**
```swift
import SwiftJWT

struct TokenClaims: Claims {
    let iss: String  // issuer
    let exp: Date    // expiration
    let sub: String  // subject
}

class JWTManager {
    func validateToken(_ tokenString: String) throws -> TokenClaims {
        let jwt = try JWT<TokenClaims>(jwtString: tokenString)
        
        // Verify signature (implementation depends on key type)
        let verifier = JWTVerifier.rs256(publicKey: publicKeyData)
        
        guard jwt.validateClaims() else {
            throw JWTError.invalidClaims
        }
        
        return jwt.claims
    }
}
```

### Animation and UI
**Libraries**: `lottie-ios`, `MBProgressHUD`

**Lottie Integration:**
```swift
import Lottie

class AnimatedLoadingView: UIView {
    private let animationView = LottieAnimationView()
    
    func setupAnimation() {
        if let animation = LottieAnimation.named("loading_animation") {
            animationView.animation = animation
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            
            addSubview(animationView)
            // Setup constraints...
        }
    }
    
    func startAnimating() {
        animationView.play()
    }
    
    func stopAnimating() {
        animationView.stop()
    }
}
```

## API Integration Patterns

### Async/Await Pattern (Modern)
```swift
protocol ServiceProtocol {
    func performOperation() async throws -> ResultType
}

class ModernService: ServiceProtocol {
    func performOperation() async throws -> ResultType {
        // Validation
        try validatePreconditions()
        
        // Network request
        let response = try await networkClient.request(.endpoint)
        
        // Processing
        let result = try processResponse(response)
        
        // Persistence
        try await persistResult(result)
        
        return result
    }
}
```

### Completion Handler Pattern (Legacy)
```objc
@interface LegacyService : NSObject
- (void)performOperationWithCompletion:(void (^)(ResultType *result, NSError *error))completion;
@end

@implementation LegacyService
- (void)performOperationWithCompletion:(void (^)(ResultType *result, NSError *error))completion {
    [self.networkClient requestWithCompletion:^(NetworkResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        ResultType *result = [self processResponse:response];
        completion(result, nil);
    }];
}
@end
```

### Error Handling Patterns
```swift
enum ServiceError: Error, LocalizedError {
    case networkError(underlying: Error)
    case authenticationRequired
    case invalidResponse
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationRequired:
            return NSLocalizedString("Authentication required", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from server", comment: "")
        case .serviceUnavailable:
            return NSLocalizedString("Service temporarily unavailable", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authenticationRequired:
            return NSLocalizedString("Please sign in to continue", comment: "")
        case .serviceUnavailable:
            return NSLocalizedString("Please try again later", comment: "")
        default:
            return nil
        }
    }
}
```

## Configuration Management

### Environment-Based Configuration
```swift
enum EnvironmentConfig {
    static var baseURL: String {
        #if DEBUG
        return "https://api-dev.example.com"
        #elseif TESTNET
        return "https://api-testnet.example.com"
        #else
        return "https://api.example.com"
        #endif
    }
    
    static var isLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
```

### Service Registration Pattern
```swift
protocol ServiceRegistry {
    func register<T>(_ service: T, for type: T.Type)
    func resolve<T>(_ type: T.Type) -> T?
}

class DIContainer: ServiceRegistry {
    private var services: [String: Any] = [:]
    
    func register<T>(_ service: T, for type: T.Type) {
        let key = String(describing: type)
        services[key] = service
    }
    
    func resolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        return services[key] as? T
    }
}

// Usage
let container = DIContainer()
container.register(CoinbaseService(), for: CoinbaseServiceProtocol.self)

// Later...
let coinbaseService = container.resolve(CoinbaseServiceProtocol.self)
```

## SwiftUI-First Integration Patterns (Updated)

### Modern SwiftUI Service Integration
**MANDATORY**: All new external service integrations MUST use SwiftUI-first architecture

```swift
// ExternalServiceView.swift - SwiftUI View (REQUIRED)
struct ExternalServiceView: View {
    @StateObject private var viewModel = ExternalServiceViewModel()

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let errorMessage = viewModel.errorMessage {
                ErrorView(message: errorMessage)
            } else {
                ServiceContentView(data: viewModel.serviceData)
            }
        }
        .task {
            await viewModel.authenticate()
        }
    }
}

// ExternalServiceViewModel.swift - ObservableObject (REQUIRED)
@MainActor
class ExternalServiceViewModel: ObservableObject {
    @Published var serviceData: ServiceData?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: ExternalServiceProtocol

    init(service: ExternalServiceProtocol = ExternalService.shared) {
        self.service = service
    }

    func authenticate() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.authenticate()
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Feature Flag Integration Patterns
**Critical Pattern**: Safe conditional compilation for external services

```swift
// SAFE - Conditional service registration
enum ExternalProvider: CaseIterable {
    case service1
    #if FEATURE_SERVICE_2_ENABLED
    case service2
    #endif
}

// SAFE - Repository factory with feature flags
class ServiceFactory {
    static func createService(provider: ExternalProvider) -> any ExternalServiceProtocol {
        switch provider {
        case .service1:
            return Service1.shared
        #if FEATURE_SERVICE_2_ENABLED
        case .service2:
            return Service2.shared
        #endif
        }
    }
}

// SAFE - ViewModel with conditional services
@MainActor
class IntegrationViewModel: ObservableObject {
    private let services: [ExternalProvider: any ExternalServiceProtocol] = {
        var dict: [ExternalProvider: any ExternalServiceProtocol] = [
            .service1: Service1.shared
        ]
        #if FEATURE_SERVICE_2_ENABLED
        dict[.service2] = Service2.shared
        #endif
        return dict
    }()
}
```

### UIKit Wrapper Pattern (Only When Necessary)
**Use ONLY for**: OAuth web flows, complex authentication UIs

```swift
// WebAuthWrapper.swift - Thin UIKit wrapper for OAuth
struct WebAuthWrapper: UIViewControllerRepresentable {
    let authURL: URL
    let onCompletion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: authURL)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
}

// Usage in SwiftUI service integration
struct ServiceAuthView: View {
    @StateObject private var viewModel = ServiceAuthViewModel()

    var body: some View {
        VStack {
            if viewModel.showingWebAuth {
                WebAuthWrapper(authURL: viewModel.authURL) { result in
                    await viewModel.handleAuthResult(result)
                }
            } else {
                AuthenticatedServiceView()
            }
        }
    }
}
```

This comprehensive integration guide provides the foundation for understanding, maintaining, and extending the external service integrations in the Dash Wallet iOS project, with mandatory SwiftUI-first architecture requirements and safe feature flag patterns.