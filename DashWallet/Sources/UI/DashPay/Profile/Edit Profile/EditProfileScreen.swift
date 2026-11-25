//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DashUIKit
import SwiftUI
import UIKit

#if DASHPAY

// MARK: - EditProfileViewModel

/// The profile being edited: display name, about text and a newly picked
/// avatar, compared with the identity's saved profile.
@MainActor
final class EditProfileViewModel: ObservableObject {
    static let displayNameLimit = 25
    static let aboutMeLimit = 250

    @Published var displayName: String
    @Published var aboutMe: String
    /// Set once a new avatar is picked: the image shown and handed to the
    /// SDK for its hashes, and the URL saved in the profile.
    @Published private(set) var pickedAvatarImage: UIImage?
    @Published private(set) var pickedAvatarURL: String?

    let usernames: [String]
    private let savedDisplayName: String
    private let savedAboutMe: String
    private let savedAvatarURL: String?

    init(identity: DWCurrentUserIdentityInfo = .shared) {
        savedDisplayName = identity.displayTitle ?? ""
        savedAboutMe = identity.publicMessage ?? ""
        savedAvatarURL = identity.avatarURL
        displayName = savedDisplayName
        aboutMe = savedAboutMe
        usernames = identity.usernames
    }

    /// The URL to save: the picked one, or the one already on the profile.
    var avatarURLString: String? { pickedAvatarURL ?? savedAvatarURL }
    var currentAvatarURL: String? { savedAvatarURL }

    var isDisplayNameTooLong: Bool { displayName.count > Self.displayNameLimit }
    var isAboutMeTooLong: Bool { aboutMe.count > Self.aboutMeLimit }
    var isValid: Bool { !isDisplayNameTooLong && !isAboutMeTooLong }

    var hasChanges: Bool {
        displayName != savedDisplayName || aboutMe != savedAboutMe || pickedAvatarURL != nil
    }

    func pickAvatar(_ image: UIImage, url: String) {
        pickedAvatarImage = image
        pickedAvatarURL = url
    }
}

// MARK: - EditProfileScreen

struct EditProfileScreen: View {
    private enum Field { case displayName, aboutMe }

    @ObservedObject var viewModel: EditProfileViewModel
    let onClose: () -> Void
    let onSave: () -> Void
    let onEditAvatar: () -> Void
    let onCopyUsername: (String) -> Void

    @FocusState private var focusedField: Field?
    @State private var showsSaveDialog = false

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    DashUIKit.NavigationBarElement.close.button(action: close)
                },
                central: {
                    Text(NSLocalizedString("Edit Profile", comment: ""))
                        .dashFont(.subheadMedium)
                        .foregroundColor(.dash.primaryText)
                })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    avatar
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                        .padding(.bottom, 64)

                    ProfileTextField(
                        title: NSLocalizedString("Display Name", comment: ""),
                        text: $viewModel.displayName,
                        limit: EditProfileViewModel.displayNameLimit,
                        isMultiline: false,
                        isFocused: focusedField == .displayName)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .aboutMe }

                    ProfileTextField(
                        title: NSLocalizedString("About me", comment: ""),
                        text: $viewModel.aboutMe,
                        limit: EditProfileViewModel.aboutMeLimit,
                        isMultiline: true,
                        isFocused: focusedField == .aboutMe)
                        .focused($focusedField, equals: .aboutMe)

                    if !viewModel.usernames.isEmpty {
                        usernames
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            // Hidden while typing, as before: above the keyboard it would
            // cover the field's character counter.
            if focusedField == nil {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Save", comment: ""),
                    isEnabled: viewModel.isValid,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onSave)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(uiColor: .dw_secondaryBackground()).ignoresSafeArea())
        .overlay {
            if showsSaveDialog {
                saveDialog
            }
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = viewModel.pickedAvatarImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    CurrentUserAvatar(urlString: viewModel.currentAvatarURL)
                }
            }
            .frame(width: 134, height: 134)
            .clipShape(Circle())

            Button(action: onEditAvatar) {
                Image("dp_avatar_edit")
                    .frame(width: 46, height: 45)
            }
            .accessibilityLabel(Text(NSLocalizedString("Change profile picture", comment: "Edit profile: VoiceOver label of the button on the avatar")))
        }
    }

    private var usernames: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("DPNS Names", comment: "Edit profile — usernames list section header"))
                .font(.footnote)
                .foregroundColor(Color(uiColor: .dw_secondaryText()))

            VStack(spacing: 0) {
                ForEach(Array(viewModel.usernames.enumerated()), id: \.offset) { index, name in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(uiColor: .dw_separatorLine()))
                            .frame(height: 1 / UIScreen.main.scale)
                    }
                    Button { onCopyUsername(name) } label: {
                        Text(name)
                            .font(.body)
                            .foregroundColor(Color(uiColor: .dw_darkTitle()))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(NSLocalizedString("Copy", comment: "")))
                }
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .dw_background()))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    /// DashUIKit's `ModalDialog` card, with the two answers side by side.
    private var saveDialog: some View {
        ZStack {
            Color.dash.backgroundOverlay.ignoresSafeArea()
            VStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Save Changes", comment: ""))
                        .dashFont(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(NSLocalizedString("Would you like to save the changes you made to your profile?", comment: ""))
                        .dashFont(.subhead)
                }
                .foregroundStyle(Color.dash.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)

                HStack(spacing: 10) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("No", comment: ""),
                        fillsWidth: true, size: .medium, style: .tintedGray) {
                            showsSaveDialog = false
                            onClose()
                        }
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Yes", comment: ""),
                        fillsWidth: true, size: .medium, style: .tintedGray) {
                            showsSaveDialog = false
                            onSave()
                        }
                }
            }
            .padding(.top, 30)
            .padding([.horizontal, .bottom], 20)
            .frame(maxWidth: 330)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .accessibilityAddTraits(.isModal)
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }

    /// Asks before dropping unsaved changes.
    private func close() {
        focusedField = nil
        if viewModel.hasChanges {
            withAnimation(.easeOut(duration: 0.2)) { showsSaveDialog = true }
        } else {
            onClose()
        }
    }
}

// MARK: - ProfileTextField

/// A titled input with a character counter, shown while the field is
/// focused or over the limit (then in red).
private struct ProfileTextField: View {
    let title: String
    @Binding var text: String
    let limit: Int
    let isMultiline: Bool
    let isFocused: Bool

    private var isTooLong: Bool { text.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(Font(UIFont.dw_font(forTextStyle: .body)))
                .foregroundColor(Color(uiColor: .dw_secondaryText()))

            Group {
                if isMultiline {
                    TextField("", text: $text, axis: .vertical)
                        .lineLimit(5...)
                } else {
                    TextField("", text: $text)
                        .autocorrectionDisabled(true)
                }
            }
            .font(Font(UIFont.dw_font(forTextStyle: .body)).weight(.medium))
            .foregroundColor(Color(uiColor: .dw_darkTitle()))
            .accessibilityLabel(Text(title))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .dw_background()))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(counter)
                .font(Font(UIFont.dw_font(forTextStyle: .callout)))
                .foregroundColor(Color(uiColor: isTooLong ? .dw_red() : .dw_secondaryText()))
                .opacity(isFocused || isTooLong ? 1 : 0)
                .accessibilityHidden(!(isFocused || isTooLong))
        }
        .padding(.vertical, 5)
    }

    private var counter: String {
        String(format: NSLocalizedString("%ld/%ld Characters", comment: "10/20 Characters"), text.count, limit)
    }
}

// MARK: - CurrentUserAvatar

/// The saved avatar, loaded the way the rest of DashPay loads it (crop
/// parameters in the URL, SDWebImage cache), with the default placeholder.
private struct CurrentUserAvatar: UIViewRepresentable {
    let urlString: String?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: "dp_current_user_placeholder"))
        imageView.contentMode = .scaleAspectFill
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.dw_setAvatar(withURLString: urlString ?? "") { [weak imageView] image in
            imageView?.image = image ?? UIImage(named: "dp_current_user_placeholder")
        }
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) { }
}

#endif
