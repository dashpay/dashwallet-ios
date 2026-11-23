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

import CryptoKit
import DashUIKit
import SwiftUI
import UIKit

#if DASHPAY

// MARK: - AvatarSourceSheet

/// Where a new avatar comes from: Gravatar, a public URL, the camera or the
/// photo library. Gravatar and the URL are entered here; the camera and the
/// library are UIKit pickers the host opens once this sheet is gone.
struct AvatarSourceSheet: View {
    enum Page { case sources, gravatar, publicURL }

    let currentURL: String?
    let onPickPhoto: (UIImagePickerController.SourceType) -> Void
    let onLoad: (_ image: UIImage, _ url: URL, _ shouldCrop: Bool) -> Void

    @State private var page: Page = .sources
    @StateObject private var model = ExternalAvatarSourceModel()

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: title,
            showBackButton: Binding(get: { page != .sources }, set: { _ in }),
            onBackButtonPressed: showSources,
            animatesHeightChanges: true
        ) {
            switch page {
            case .sources:
                sources
            case .gravatar, .publicURL:
                ExternalAvatarSourceForm(model: model, onLoad: onLoad)
            }
        }
    }

    private var title: String {
        switch page {
        case .sources: NSLocalizedString("Change profile picture", comment: "Edit profile: VoiceOver label of the button on the avatar")
        case .gravatar: "Gravatar"
        case .publicURL: NSLocalizedString("Public URL", comment: "")
        }
    }

    private var sources: some View {
        VStack(spacing: 0) {
            DashUIKit.MenuItem(leadingIcon: .custom("dp_avatar_gravatar"), title: "Gravatar") {
                open(.gravatar)
            }
            DashUIKit.MenuItem(leadingIcon: .custom("dp_avatar_url"), title: NSLocalizedString("Public URL", comment: "")) {
                open(.publicURL)
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                DashUIKit.MenuItem(leadingIcon: .custom("dp_avatar_photo"), title: NSLocalizedString("Take a Photo from Camera", comment: "")) {
                    onPickPhoto(.camera)
                }
            }
            DashUIKit.MenuItem(leadingIcon: .custom("dp_avatar_gallery"), title: NSLocalizedString("Select from Gallery", comment: "")) {
                onPickPhoto(.photoLibrary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func open(_ page: Page) {
        model.configure(page == .gravatar ? .gravatar : .publicURL(current: currentURL))
        withAnimation { self.page = page }
    }

    private func showSources() {
        model.cancel()
        withAnimation { page = .sources }
    }
}

// MARK: - ExternalAvatarSourceForm

private struct ExternalAvatarSourceForm: View {
    @ObservedObject var model: ExternalAvatarSourceModel
    let onLoad: (_ image: UIImage, _ url: URL, _ shouldCrop: Bool) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.error ?? model.kind.subtitle)
                .dashFont(.subhead)
                .foregroundStyle(model.error == nil ? Color.dash.secondaryText : Color.dash.red)
                .fixedSize(horizontal: false, vertical: true)

            TextInput(
                label: model.kind.inputLabel,
                text: $model.input,
                isError: model.error != nil,
                keyboardType: model.kind.keyboardType,
                autocapitalization: .never,
                isEnabled: !model.isLoading,
                onSubmit: load,
                focus: $isFocused)

            Text(model.kind.description)
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            DashUIKit.DashButton(
                text: model.isLoading ? NSLocalizedString("Fetching Image", comment: "") : NSLocalizedString("OK", comment: ""),
                isEnabled: !model.isLoading,
                isLoading: model.isLoading,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: load)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .onAppear { isFocused = true }
        .onDisappear { model.cancel() }
        .onChange(of: model.input) { _ in model.error = nil }
    }

    private func load() {
        isFocused = false
        model.load { image, url in onLoad(image, url, model.kind.shouldCrop) }
    }
}

// MARK: - ExternalAvatarSourceModel

/// Checks the entered email or URL and downloads the image it points to.
@MainActor
final class ExternalAvatarSourceModel: ObservableObject {
    enum Kind: Equatable {
        case gravatar
        case publicURL

        var subtitle: String {
            switch self {
            case .gravatar: NSLocalizedString("Enter your Gravatar Email ID", comment: "")
            case .publicURL: NSLocalizedString("Paste your image URL", comment: "")
            }
        }

        var description: String {
            switch self {
            case .gravatar:
                NSLocalizedString("Your Email is not stored in the DashPay wallet nor on any servers. It is used once to get your Gravatar account details and then discarded.", comment: "")
            case .publicURL:
                NSLocalizedString("You can specify any URL which is publicly available on the internet so other users can see it on the Dash network.", comment: "")
            }
        }

        var inputLabel: String {
            switch self {
            case .gravatar: NSLocalizedString("Email", comment: "")
            case .publicURL: NSLocalizedString("Link", comment: "")
            }
        }

        var keyboardType: UIKeyboardType { self == .gravatar ? .emailAddress : .URL }
        /// A Gravatar image is already square; any other picture is cropped.
        var shouldCrop: Bool { self == .publicURL }
    }

    enum Source {
        case gravatar
        case publicURL(current: String?)
    }

    static let maxURLLength = 256

    @Published private(set) var kind: Kind = .gravatar
    @Published var input = ""
    @Published var error: String?
    @Published private(set) var isLoading = false
    private var task: Task<Void, Never>?

    func configure(_ source: Source) {
        cancel()
        error = nil
        switch source {
        case .gravatar:
            kind = .gravatar
            input = ""
        case .publicURL(let current):
            kind = .publicURL
            input = current ?? ""
        }
    }

    func load(onLoad: @escaping (UIImage, URL) -> Void) {
        guard !isLoading else { return }
        let url: URL
        switch Self.imageURL(for: input, kind: kind) {
        case .success(let value): url = value
        case .failure(let failure):
            error = failure.message
            return
        }

        isLoading = true
        task = Task { [weak self] in
            let image = await Self.download(url)
            guard let self, !Task.isCancelled else { return }
            self.isLoading = false
            if let image {
                onLoad(image, url)
            } else {
                self.error = self.kind == .gravatar
                    ? NSLocalizedString("Unable to fetch your Gravatar. Please enter a valid gravatar email ID.", comment: "")
                    : NSLocalizedString("Unable to fetch image. Please enter a valid image URL or check your connection.", comment: "")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    // MARK: Input rules

    struct InputError: Error, Equatable {
        let message: String
    }

    static func imageURL(for input: String, kind: Kind) -> Result<URL, InputError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .gravatar:
            guard isValidEmail(trimmed) else {
                return .failure(InputError(message: NSLocalizedString("Please enter a valid gravatar email ID.", comment: "")))
            }
            // 200px, and a 404 instead of a default picture when there is none.
            return .success(URL(string: "https://www.gravatar.com/avatar/\(md5(trimmed))?s=200&d=404")!)

        case .publicURL:
            let invalid = InputError(message: NSLocalizedString("Please enter a valid image URL.", comment: ""))
            guard !trimmed.isEmpty else { return .failure(invalid) }
            guard trimmed.count <= maxURLLength else {
                return .failure(InputError(message: String(
                    format: NSLocalizedString("Image URL can't be longer than %ld characters.", comment: ""),
                    maxURLLength)))
            }
            guard let url = directImageURL(trimmed) else { return .failure(invalid) }
            return .success(url)
        }
    }

    static func isValidEmail(_ email: String) -> Bool {
        email.range(of: "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$", options: .regularExpression) != nil
    }

    static func md5(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Google Drive and Dropbox share links point to a web page; these are
    /// their direct image links.
    static func directImageURL(_ link: String) -> URL? {
        let googlePrefix = "https://drive.google.com/file/d/"
        if link.hasPrefix(googlePrefix) {
            let rest = link.dropFirst(googlePrefix.count)
            if let slash = rest.firstIndex(of: "/") {
                return URL(string: "https://drive.google.com/uc?export=view&id=\(rest[..<slash])")
            }
        }
        let dropboxPrefix = "https://www.dropbox.com/s/"
        if link.hasPrefix(dropboxPrefix) {
            return URL(string: "https://dl.dropboxusercontent.com/s/" + link.dropFirst(dropboxPrefix.count))
        }
        return URL(string: link)
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return UIImage(data: data)
    }
}

#endif
