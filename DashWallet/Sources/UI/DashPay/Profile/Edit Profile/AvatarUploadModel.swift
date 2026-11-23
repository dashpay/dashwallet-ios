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

import Combine
import UIKit

#if DASHPAY

// MARK: - AvatarUploadModel

/// Uploads a cropped avatar to Imgur. The previous upload, if this wallet
/// made one, is deleted first through the delete hash kept in user defaults.
@MainActor
final class AvatarUploadModel: ObservableObject {
    enum State: Equatable {
        case loading
        case error
        case success
    }

    static let deleteHashKey = "ImgurImageDeleteHash"

    let image: UIImage
    @Published private(set) var state: State = .loading
    @Published private(set) var resultURLString: String?
    /// The reason to show instead of the generic error, when there is one.
    @Published private(set) var failureMessage: String?
    @Published private(set) var failureIsRetryable = true

    private let client: DWAvatarUploadClient
    private var operation: DWAvatarUploadCancelling?
    /// Bumped on every retry and cancel: a completion from an earlier
    /// attempt is dropped.
    private var generation = 0

    init(image: UIImage, client: DWAvatarUploadClient = DWAvatarUploadClient()) {
        self.image = image
        self.client = client
        retry()
    }

    func retry() {
        operation?.cancel()
        generation += 1
        let attempt = generation
        failureMessage = nil
        failureIsRetryable = true
        state = .loading

        let deleteHash = UserDefaults.standard.string(forKey: Self.deleteHashKey)
        operation = client.upload(image: image, deleteHash: deleteHash) { [weak self] link, newDeleteHash, error in
            Task { @MainActor [weak self] in
                self?.finish(attempt: attempt, link: link, deleteHash: newDeleteHash, error: error)
            }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
    }

    private func finish(attempt: Int, link: String?, deleteHash: String?, error: NSError?) {
        guard attempt == generation else { return }
        operation = nil

        if let error {
            // Missing credentials, or a host that refused the action outright:
            // neither can succeed on a retry, so no retry is offered. Rate
            // limits, 5xx and transport errors stay retryable.
            let permanent = error.domain == DWAvatarUploadClient.errorDomain
                && [DWAvatarUploadClient.errorCodeNotConfigured, DWAvatarUploadClient.errorCodeRefused].contains(error.code)
            failureIsRetryable = !permanent
            failureMessage = permanent ? error.localizedDescription : nil
            state = .error
            return
        }

        if let deleteHash, !deleteHash.isEmpty {
            UserDefaults.standard.set(deleteHash, forKey: Self.deleteHashKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.deleteHashKey)
        }
        resultURLString = link
        state = .success
    }
}

#endif
