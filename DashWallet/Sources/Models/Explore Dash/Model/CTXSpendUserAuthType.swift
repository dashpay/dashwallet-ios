import Foundation

enum CTXSpendUserAuthType {
    case createAccount
    case signIn
    case otp
    
    var screenTitle: String {
        switch self {
        case .createAccount:
            return NSLocalizedString("Create CTXSpend Account", comment: "Create CTXSpend Account")
        case .signIn:
            return NSLocalizedString("Log in to CTXSpend Account", comment: "Log in to CTXSpend Account")
        case .otp:
            return NSLocalizedString("Enter Verification Code", comment: "Enter Verification Code")
        }
    }
    
    var screenSubtitle: String {
        switch self {
        case .createAccount, .signIn:
            return NSLocalizedString("Log in to CTXSpend account to buy gift cards", comment: "Log in to CTXSpend account to buy gift cards")
        case .otp:
            return NSLocalizedString("Please check your email for the verification code", comment: "Please check your email for the verification code")
        }
    }
    
    var textInputHint: String {
        switch self {
        case .createAccount, .signIn:
            return NSLocalizedString("Email", comment: "Email")
        case .otp:
            return NSLocalizedString("Verification Code", comment: "Verification Code")
        }
    }
} 