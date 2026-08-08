//
//  ContactsSearchField.swift
//  DashWallet
//
//  Rounded search field used by the contacts and add-contact screens.
//

import SwiftUI
import DashUIKit

struct ContactsSearchField: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 45

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.dash.tertiaryText)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.dash.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground)
                .shadow(color: .shadow, radius: 4, y: 1))
    }
}

/// Android white card container (8pt radius) used for row groups.

#if DEBUG

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ContactsSearchField(placeholder: "Search Contacts", text: .constant(""))
        ContactsSearchField(placeholder: "Search Contacts", text: .constant("briantest"))
    }
    .padding()
    .background(Color.dash.primaryBackground)
}

#endif
