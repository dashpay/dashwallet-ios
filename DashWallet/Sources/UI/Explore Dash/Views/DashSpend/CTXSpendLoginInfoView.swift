import SwiftUI

struct CTXSpendLoginInfoView: View {
    let onCreateNewAccount: () -> Void
    let onLogIn: () -> Void
    let onTermsAndConditions: () -> Void
    @State private var inProgress: Bool = false
    
    var body: some View {
        BottomSheet(showBackButton: .constant(false)) {
            VStack {
                TextIntro(
                    icon: .custom("ctx.logo", maxHeight: 60),
                    inProgress: $inProgress
                ) {
                    FeatureTopText(
                        title: NSLocalizedString("Create an account or log into an existing one", comment: "DashSpend account title"),
                        label: NSLocalizedString("Terms & conditions", comment: "Terms & conditions"),
                        labelIcon: .custom("external.link"),
                        linkAction: onTermsAndConditions
                    )
                }
                
                ButtonsGroup(
                    orientation: .vertical,
                    size: .large,
                    positiveActionEnabled: true,
                    positiveButtonText: NSLocalizedString("Create new account", comment: ""),
                    positiveButtonAction: {
                        onCreateNewAccount()
                    },
                    negativeButtonText: NSLocalizedString("Log in", comment: ""),
                    negativeButtonAction: {
                        onLogIn()
                    }
                )
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    CTXSpendLoginInfoView(
        onCreateNewAccount: {},
        onLogIn: {},
        onTermsAndConditions: {}
    )
}
