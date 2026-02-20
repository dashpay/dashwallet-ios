import SwiftUI

struct ConfirmSpendDialog: View {
    @State private var isAccepted: Bool = false
    
    let username: String
    let amount: Int64
    var onCancel: () -> Void
    var onConfirm: () -> Void
    
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
            
            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 15)
            
            DashAmount(amount: amount, font: .largeTitle, dashSymbolFactor: 0.7, showDirection: false)
                .padding(.top, 15)
            FormattedFiatText(from: amount)
            
            VStack(spacing: 4) {
                Text(String.localizedStringWithFormat(NSLocalizedString("You chose “%@” as your username.", comment: "Usernames"), username))
                    .font(.subhead)
                Text(NSLocalizedString("Please note that the username can NOT be changed once it is registered.", comment: "Usernames"))
                    .font(.subhead)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 15)
            
            Toggle(isOn: $isAccepted) {
                Text(NSLocalizedString("I accept", comment: ""))
                    .font(.system(size: 15))
                    .padding(.leading, 4)
            }
            .onTapGesture {
                isAccepted.toggle()
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.top, 19)
            
            Spacer()
            
            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveActionEnabled: isAccepted,
                positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                positiveButtonAction: {
                    if isAccepted {
                        onConfirm()
                    }
                },
                negativeButtonText: NSLocalizedString("Cancel", comment: ""),
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
            .font(.subhead)
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
