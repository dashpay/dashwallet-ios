import SwiftUI

struct CTXSpendUserAuthView: View {
    @StateObject private var viewModel = CTXSpendUserAuthViewModel()
    let authType: CTXSpendUserAuthType
    let onSuccess: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(authType.screenTitle)
                    .font(.headline)
                    .padding(.top, 20)
                
                Text(authType.screenSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 8) {
                    TextField(authType.textInputHint, text: $viewModel.input)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(authType == .otp ? .numberPad : .emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if viewModel.showError {
                        Text(viewModel.errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                
                if authType == .otp {
                    NumericKeyboardView(value: $viewModel.input)
                        .frame(height: 200)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await viewModel.continueAction(authType: authType, onSuccess: onSuccess)
                    }
                }) {
                    if viewModel.isLoading {
                        SwiftUI.ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(NSLocalizedString("Continue", comment: "Continue"))
                    }
                }
                .disabled(!viewModel.isInputValid(authType: authType) || viewModel.isLoading)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button(action: {
                // TODO: Dismiss
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.primaryText)
            })
        }
    }
}

class CTXSpendUserAuthViewModel: ObservableObject {
    @Published var input = ""
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let service = CTXSpendService()
    
    func isInputValid(authType: CTXSpendUserAuthType) -> Bool {
        if authType == .otp {
            return !input.isEmpty
        }
        return input.isValidEmail
    }
    
    func continueAction(authType: CTXSpendUserAuthType, onSuccess: @escaping () -> Void) async {
        isLoading = true
        showError = false
        
        do {
            switch authType {
            case .createAccount, .signIn:
                let success = try await service.signIn(email: input, isSignIn: authType == .signIn)
                if success {
                    // TODO: Navigate to OTP screen
                }
            case .otp:
                let success = try await service.verifyEmail(code: input)
                if success {
                    onSuccess()
                }
            }
        } catch CTXSpendError.invalidCode {
            showError = true
            errorMessage = NSLocalizedString("Invalid verification code", comment: "Invalid verification code")
        } catch {
            showError = true
            errorMessage = NSLocalizedString("An error occurred", comment: "An error occurred")
        }
        
        isLoading = false
    }
}

private extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
} 
