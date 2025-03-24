import SwiftUI

struct ConfirmSpendDialog: View {
    @State private var isAccepted: Bool = false
    
    let amount: Int64
    var title: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var username: String? = nil
    var detailsText: String? = nil
    var requiresAcceptance: Bool = false
    var acceptanceText: String = NSLocalizedString("I accept", comment: "")
    var confirmButtonText: String = NSLocalizedString("Confirm", comment: "")
    var cancelButtonText: String = NSLocalizedString("Cancel", comment: "")
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
                    .frame(width: 36, height: 5)
                    .cornerRadius(2.50)
                Spacer()
            }
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 15)
            
            DashAmount(amount: amount, font: .largeTitle, dashSymbolFactor: 0.7, showDirection: false)
                .padding(.top, 15)
            FormattedFiatText(from: amount)
            
            if username != nil || detailsText != nil {
                VStack(spacing: 4) {
                    if let username = username {
                        Text(String.localizedStringWithFormat(NSLocalizedString("You chose \"%@\" as your username.", comment: "Usernames"), username))
                            .font(.body2)
                    }
                    
                    if let detailsText = detailsText {
                        Text(detailsText)
                            .font(.body2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 15)
            }
            
            if requiresAcceptance {
                Toggle(isOn: $isAccepted) {
                    Text(acceptanceText)
                        .font(.system(size: 15))
                        .padding(.leading, 4)
                }
                .onTapGesture {
                    isAccepted.toggle()
                }
                .toggleStyle(CheckboxToggleStyle())
                .padding(.top, 19)
            }
            
            Spacer()
            
            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveActionEnabled: !requiresAcceptance || isAccepted,
                positiveButtonText: confirmButtonText,
                positiveButtonAction: {
                    if !requiresAcceptance || isAccepted {
                        onConfirm()
                    }
                },
                negativeButtonText: cancelButtonText,
                negativeButtonAction: {
                    onCancel()
                }
            )
            .padding(.horizontal)
            
        }
        .padding()
    }
    
    @ViewBuilder
    private func FormattedFiatText(from dashAmount: Int64) -> some View {
        let text = (try? CurrencyExchanger.shared.convertDash(amount: abs(dashAmount.dashAmount), to: App.fiatCurrency).formattedFiatAmount) ?? NSLocalizedString("Not available", comment: "")
        Text(text)
            .font(.body2)
            .foregroundColor(.secondaryText)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(configuration.isOn ? "icon_checkbox_square_checked" : "icon_checkbox_square")
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}
