//
//  MyDashPayUserQRSheet.swift
//  DashWallet
//
//  The current user's own scannable contact code.
//
//  Ported verbatim from the add-contact screen this branch replaced (#947);
//  only its home changed — the code belongs on the owner's profile, while the
//  scanner lives on the contacts list where people are added.
//

import SwiftUI
import DashUIKit

struct MyDashPayUserQRSheet: View {
    let link: DashPayUserLink
    let displayName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 6) {
                    Text(displayName ?? link.username)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                        .padding(.top, 20)
                    if displayName != nil {
                        Text(link.username)
                            .font(.system(size: 14))
                            .foregroundColor(.dash.secondaryText)
                    }
                    Group {
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            SwiftUI.ProgressView()
                        }
                    }
                    .frame(width: 240, height: 240)
                    .padding(20)
                    // The branded QR draws Dash-blue modules on a
                    // transparent background — keep the card white in
                    // dark mode so camera scanners keep their contrast.
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.dash.shadow, radius: 16, x: 0, y: 4))
                    .padding(.top, 14)
                    Text(NSLocalizedString("Let another Dash Wallet user scan this code to add you as a contact.", comment: "DashPay Contacts: caption under the user's own QR code"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, 14)
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if qrImage == nil {
                qrImage = QRCodeGenerator.dashStyledImage(for: link.uriString, size: 240)
            }
        }
    }
}
