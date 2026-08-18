//
//  TransferTimingSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// Why a shielded transfer is instant one way and slow the other, shown once
/// before the first internal transfer.
///
/// `fillsHeight: false` rather than `BottomSheet.selfSizing`: the host presents
/// this from UIKit, and SwiftUI's `.presentationDetents` does not bridge to a
/// `UIHostingController` shown with `present()`. `PaymentsLandingHostingController`
/// measures the content and sets a matching UIKit detent instead.
struct TransferTimingSheet: View {
    var onConfirm: () -> Void

    var body: some View {
        DashUIKit.BottomSheet(
            showBackButton: .constant(false),
            fillsHeight: false
        ) {
            VStack(alignment: .leading, spacing: 0) {

                VStack(alignment: .leading, spacing: 20) {
                    Text(NSLocalizedString("Transfers take different times", comment: "Payments"))
                        .dashFont(.title1)
                        .foregroundStyle(Color.dash.primaryText)

                    VStack(alignment: .leading, spacing: 16) {
                        SheetFeature(
                            title: NSLocalizedString("From Dash Wallet to Shielded balance", comment: "Payments"),
                            description: NSLocalizedString("The transfer is instant", comment: "Payments"),
                            icon: .custom("feature-instant", bundle: .dashUIKit),
                            iconColor: .dash.yellow
                        )

                        SheetFeature(
                            title: NSLocalizedString("From Shielded balance to Dash Wallet", comment: "Payments"),
                            description: NSLocalizedString("The transfer could take up to 10 minutes", comment: "Payments"),
                            icon: .custom("feature-timer-purple", bundle: .dashUIKit)
                        )
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .padding(.bottom, 32)

                DashButton(
                    text: NSLocalizedString("I got it", comment: "Payments"),
                    style: .filledBlue,
                    size: .large,
                    action: onConfirm
                )
                .padding(.horizontal, 60)
                .padding(.vertical, 20)
            }
        }
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview("Sheet") {
    Color.dash.primaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TransferTimingSheet(onConfirm: {})
        }
}

@available(iOS 17, *)
#Preview("Content") {
    TransferTimingSheet(onConfirm: {})
}

/// The rows wrap and the button must stay reachable at the largest type sizes.
@available(iOS 17, *)
#Preview("Large type") {
    TransferTimingSheet(onConfirm: {})
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
