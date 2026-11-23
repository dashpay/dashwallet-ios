//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if DASHPAY
protocol RootEditProfileViewControllerDelegate: AnyObject {
    /// `avatarImage` is the picked image (or `nil` if the avatar wasn't
    /// changed in this session). The SDK profile-update path JPEG-encodes it
    /// and hands the bytes to `DashPayProfileUpdate.avatarBytes` for hash
    /// computation.
    func editProfileViewController(_ controller: RootEditProfileViewController, updateDisplayName rawDisplayName: String, aboutMe rawAboutMe: String, avatarURLString: String?, avatarImage: UIImage?)
    func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController)
}

/// Hosts `EditProfileScreen` and presents the avatar flows from UIKit: the
/// photo picker, and the crop screen over the whole window.
final class RootEditProfileViewController: UIHostingController<EditProfileScreen> {
    weak var delegate: RootEditProfileViewControllerDelegate?
    private let viewModel: EditProfileViewModel

    init() {
        let viewModel = EditProfileViewModel()
        self.viewModel = viewModel
        // The closures need `self`, which exists only after `super.init`.
        super.init(rootView: EditProfileScreen(
            viewModel: viewModel, onClose: {}, onSave: {}, onPickPhoto: { _ in }, onCrop: { _, _ in },
            onCopyUsername: { _ in }))
        rootView = EditProfileScreen(
            viewModel: viewModel,
            onClose: { [weak self] in
                guard let self else { return }
                self.delegate?.editProfileViewControllerDidCancel(self)
            },
            onSave: { [weak self] in self?.save() },
            onPickPhoto: { [weak self] sourceType in self?.showImagePicker(sourceType) },
            onCrop: { [weak self] image, url in self?.showCrop(image, url: url) },
            onCopyUsername: { [weak self] name in
                UIPasteboard.general.string = name
                self?.view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""), offsetForNavBar: true)
            })
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_secondaryBackground()
    }

    private func save() {
        delegate?.editProfileViewController(
            self,
            updateDisplayName: viewModel.displayName,
            aboutMe: viewModel.aboutMe,
            avatarURLString: viewModel.avatarURLString,
            avatarImage: viewModel.pickedAvatarImage)
    }

    // MARK: Avatar flows

    private func showImagePicker(_ sourceType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else { return }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        picker.mediaTypes = [UTType.image.identifier]
        present(picker, animated: true)
    }

    private func showCrop(_ image: UIImage, url: URL?) {
        let crop = UIHostingController(rootView: AvatarCropScreen(
            image: image,
            imageURL: url,
            onDone: { [weak self] image, urlString in
                self?.viewModel.pickAvatar(image, url: urlString)
                self?.dismiss(animated: true)
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) }))
        crop.modalPresentationStyle = .fullScreen
        crop.overrideUserInterfaceStyle = .dark
        present(crop, animated: true)
    }
}

// MARK: UIImagePickerControllerDelegate

extension RootEditProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true) { [weak self] in
            guard let image else { return }
            self?.showCrop(image, url: nil)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

#else
protocol RootEditProfileViewControllerDelegate: AnyObject { }
#endif
