//
//  DWAvatarUploadClient.swift
//  DashWallet
//
//  App-owned Imgur transport used by the legacy Objective-C avatar UI.
//


import Foundation
import Moya
import UIKit

/// Imgur anonymous-upload credentials.
///
/// Read from a bundled `Imgur-Info.plist`, mirroring how `SwapKitConstants` and
/// `Coinbase+Constants` read theirs: drop the (git-ignored) plist next to the
/// others and add it to the dashwallet/dashpay targets. Absent credentials mean
/// avatar upload is unavailable in this build — `DWAvatarUploadClient` fails the
/// request up front instead of letting Imgur reject an invalid Client-ID and
/// presenting it to the user as a retryable network error.
enum DWAvatarUploadConfiguration {
    static let clientID: String = {
        guard let path = Bundle.main.path(forResource: "Imgur-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
              let clientID = dict["CLIENT_ID"] as? String
        else { return "" }
        return clientID
    }()

    static var isConfigured: Bool { !clientID.isEmpty }
}

enum DWAvatarEndpoint: TargetType {
    case delete(deleteHash: String)
    case upload(imageData: Data)

    var baseURL: URL {
        URL(string: "https://api.imgur.com")!
    }

    var path: String {
        switch self {
        case .delete(let deleteHash):
            return "/3/image/\(deleteHash)"
        case .upload:
            return "/3/upload"
        }
    }

    var method: Moya.Method {
        switch self {
        case .delete:
            return .delete
        case .upload:
            return .post
        }
    }

    var task: Moya.Task {
        switch self {
        case .delete:
            return .requestPlain
        case .upload(let imageData):
            return .uploadMultipart([
                MultipartFormData(
                    provider: .data(imageData),
                    name: "image",
                    fileName: "image.jpg",
                    mimeType: "image/jpeg")
            ])
        }
    }

    var headers: [String: String]? {
        ["Authorization": "Client-ID \(DWAvatarUploadConfiguration.clientID)"]
    }
}

@objc(DWAvatarUploadCancelling)
protocol DWAvatarUploadCancelling: AnyObject {
    func cancel()
}

private final class DWAvatarUploadTask: NSObject, DWAvatarUploadCancelling {
    private let lock = NSLock()
    private var cancelled = false
    private var currentRequest: Cancellable?
    private var requestGeneration: UInt = 0

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func beginRequest() -> UInt? {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return nil }
        requestGeneration &+= 1
        return requestGeneration
    }

    func replaceCurrentRequest(with request: Cancellable, generation: UInt) {
        lock.lock()
        let isCurrent = generation == requestGeneration
        if isCurrent && !cancelled {
            currentRequest = request
        }
        let shouldCancel = cancelled
        lock.unlock()

        if shouldCancel {
            request.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = currentRequest
        lock.unlock()
        request?.cancel()
    }
}

@objc(DWAvatarUploadClient)
final class DWAvatarUploadClient: NSObject {
    typealias UploadCompletion = (String?, String?, NSError?) -> Void

    @objc static let errorDomain = "DWAvatarUploadClient"
    /// This build ships no Imgur credentials, so no amount of retrying can make
    /// the upload succeed. The UI uses this to offer an exit instead of a
    /// "Try again" that is guaranteed to fail.
    @objc static let errorCodeNotConfigured = 2

    // Internal test seam used by DWUploadAvatarModel tests. Production callers
    // always get the normal HTTPClient and image queue.
    static var testingHTTPClient: HTTPClient<DWAvatarEndpoint>?
    static var testingImageQueue: DispatchQueue?

    private static let deleteAttemptCount = 4
    private let httpClient: HTTPClient<DWAvatarEndpoint>
    private let imageQueue: DispatchQueue

    var httpClientForTesting: HTTPClient<DWAvatarEndpoint> {
        httpClient
    }

    override convenience init() {
        if let testingHTTPClient = Self.testingHTTPClient {
            self.init(
                httpClient: testingHTTPClient,
                imageQueue: Self.testingImageQueue
                    ?? DispatchQueue(label: "org.dashfoundation.dash.avatar-upload.test-image"))
        } else {
            self.init(httpClient: HTTPClient<DWAvatarEndpoint>())
        }
    }

    init(httpClient: HTTPClient<DWAvatarEndpoint>,
         imageQueue: DispatchQueue = DispatchQueue(label: "org.dashfoundation.dash.avatar-upload.image", qos: .userInitiated)) {
        self.httpClient = httpClient
        self.imageQueue = imageQueue
        super.init()
    }

    @objc(uploadImage:deleteHash:completion:)
    func upload(
        image: UIImage,
        deleteHash: String?,
        completion: @escaping UploadCompletion
    ) -> DWAvatarUploadCancelling {
        let task = DWAvatarUploadTask()

        guard DWAvatarUploadConfiguration.isConfigured else {
            DWLogger.log("AvatarUpload: no Imgur CLIENT_ID in this build — upload refused up front")
            finish(
                task: task,
                link: nil,
                deleteHash: nil,
                error: Self.error(
                    NSLocalizedString(
                        "Picture upload is not available in this build.",
                        comment: "Avatar upload has no configured credentials"),
                    code: Self.errorCodeNotConfigured),
                completion: completion)
            return task
        }

        let startUpload = { [weak self, weak task] in
            guard let self, let task, !task.isCancelled else { return }
            self.prepareAndUpload(image: image, task: task, completion: completion)
        }

        if let deleteHash, !deleteHash.isEmpty {
            deletePreviousImage(
                deleteHash: deleteHash,
                attemptsRemaining: Self.deleteAttemptCount,
                task: task,
                completion: startUpload)
        } else {
            startUpload()
        }

        return task
    }

    private func deletePreviousImage(
        deleteHash: String,
        attemptsRemaining: Int,
        task: DWAvatarUploadTask,
        completion: @escaping () -> Void
    ) {
        guard let requestGeneration = task.beginRequest() else { return }

        let request = httpClient.request(.delete(deleteHash: deleteHash)) { [weak self, weak task] result in
            guard let self, let task, !task.isCancelled else { return }

            switch result {
            case .success:
                completion()
            case .failure:
                if attemptsRemaining > 1 {
                    self.deletePreviousImage(
                        deleteHash: deleteHash,
                        attemptsRemaining: attemptsRemaining - 1,
                        task: task,
                        completion: completion)
                } else {
                    // Avatar replacement has always been best-effort: a failed
                    // delete must not prevent the new image from uploading.
                    completion()
                }
            }
        }
        task.replaceCurrentRequest(with: request, generation: requestGeneration)
    }

    private func prepareAndUpload(
        image: UIImage,
        task: DWAvatarUploadTask,
        completion: @escaping UploadCompletion
    ) {
        imageQueue.async { [weak self, weak task] in
            guard let self, let task, !task.isCancelled else { return }

            let maxImageSide: CGFloat = 600
            let resultImage: UIImage
            if image.size.width > maxImageSide || image.size.height > maxImageSide {
                resultImage = image.dw_resize(
                    CGSize(width: maxImageSide, height: maxImageSide),
                    with: .high)
            } else {
                resultImage = image
            }

            guard let imageData = resultImage.jpegData(compressionQuality: 0.5) else {
                self.finish(
                    task: task,
                    link: nil,
                    deleteHash: nil,
                    error: Self.error("Unable to encode avatar image"),
                    completion: completion)
                return
            }

            guard let requestGeneration = task.beginRequest() else { return }
            let request = self.httpClient.request(.upload(imageData: imageData)) { [weak self, weak task] result in
                guard let self, let task, !task.isCancelled else { return }

                switch result {
                case .success(let response):
                    do {
                        let object = try JSONSerialization.jsonObject(with: response.data)
                        guard let json = object as? [String: Any],
                              (json["success"] as? NSNumber)?.boolValue == true
                        else {
                            // The status code and Imgur's own error string are the
                            // only way to tell a bad Client-ID from a rate limit or
                            // a rejected image, and neither reaches the UI.
                            DWLogger.log(
                                "AvatarUpload: Imgur rejected the upload — status \(response.statusCode), "
                                    + "body \(String(data: response.data, encoding: .utf8) ?? "<non-utf8>")")
                            throw Self.error("Imgur rejected the avatar upload")
                        }
                        let data = json["data"] as? [String: Any]
                        self.finish(
                            task: task,
                            link: data?["link"] as? String,
                            deleteHash: data?["deletehash"] as? String,
                            error: nil,
                            completion: completion)
                    } catch {
                        self.finish(
                            task: task,
                            link: nil,
                            deleteHash: nil,
                            error: error as NSError,
                            completion: completion)
                    }
                case .failure(let error):
                    DWLogger.log("AvatarUpload: transport failure — \(error.localizedDescription)")
                    self.finish(
                        task: task,
                        link: nil,
                        deleteHash: nil,
                        error: error as NSError,
                        completion: completion)
                }
            }
            task.replaceCurrentRequest(with: request, generation: requestGeneration)
        }
    }

    private func finish(
        task: DWAvatarUploadTask,
        link: String?,
        deleteHash: String?,
        error: NSError?,
        completion: @escaping UploadCompletion
    ) {
        DispatchQueue.main.async {
            guard !task.isCancelled else { return }
            completion(link, deleteHash, error)
        }
    }

    private static func error(_ description: String, code: Int = 1) -> NSError {
        NSError(
            domain: errorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description])
    }
}
