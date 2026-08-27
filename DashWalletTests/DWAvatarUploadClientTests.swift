//
//  DWAvatarUploadClientTests.swift
//  DashWalletTests
//


import Moya
import UIKit
import XCTest
@testable import dashwallet

final class DWAvatarUploadClientTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedTargets: [DWAvatarEndpoint] = []
        var onRequest: ((DWAvatarEndpoint) -> Void)?

        var targets: [DWAvatarEndpoint] {
            lock.lock()
            defer { lock.unlock() }
            return recordedTargets
        }

        func append(_ target: DWAvatarEndpoint) {
            lock.lock()
            recordedTargets.append(target)
            let callback = onRequest
            lock.unlock()
            callback?(target)
        }
    }

    private typealias Sample = EndpointSampleResponse

    override func tearDown() {
        DWAvatarUploadClient.testingHTTPClient = nil
        DWAvatarUploadClient.testingImageQueue = nil
        UserDefaults.standard.removeObject(forKey: "ImgurImageDeleteHash")
        super.tearDown()
    }

    func testMultipartEndpointContract() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let endpoint = DWAvatarEndpoint.upload(imageData: bytes)

        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://api.imgur.com")
        XCTAssertEqual(endpoint.path, "/3/upload")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.headers?["Authorization"], "Client-ID imgurId")

        guard case .uploadMultipart(let parts) = endpoint.task else {
            return XCTFail("Expected a multipart upload task")
        }
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].name, "image")
        XCTAssertEqual(parts[0].fileName, "image.jpg")
        XCTAssertEqual(parts[0].mimeType, "image/jpeg")
        guard case .data(let multipartBytes) = parts[0].provider else {
            return XCTFail("Expected in-memory image data")
        }
        XCTAssertEqual(multipartBytes, bytes)
    }

    func testDeleteEndpointContract() {
        let endpoint = DWAvatarEndpoint.delete(deleteHash: "old-hash")

        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://api.imgur.com")
        XCTAssertEqual(endpoint.path, "/3/image/old-hash")
        XCTAssertEqual(endpoint.method, .delete)
        XCTAssertEqual(endpoint.headers?["Authorization"], "Client-ID imgurId")
        guard case .requestPlain = endpoint.task else {
            return XCTFail("Expected a plain delete request")
        }
    }

    func testOversizedImageIsResizedBeforeUpload() {
        let expected = expectation(description: "resized upload succeeds")
        let recorder = Recorder()
        let client = makeClient(recorder: recorder) { _, _ in
            .networkResponse(200, Self.successBody)
        }

        let task = client.upload(
            image: Self.image(size: CGSize(width: 1200, height: 800)),
            deleteHash: nil
        ) { _, _, error in
            XCTAssertNil(error)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
        guard let lastTarget = recorder.targets.last,
              case .upload(let imageData) = lastTarget
        else {
            return XCTFail("Expected an upload request")
        }
        XCTAssertEqual(UIImage(data: imageData)?.size, CGSize(width: 600, height: 600))
    }

    func testSuccessParsesLinkAndDeleteHash() {
        let expected = expectation(description: "upload succeeds")
        let client = makeClient { target, _ in
            guard case .upload = target else { return .networkResponse(204, Data()) }
            return .networkResponse(200, Self.successBody)
        }

        let task = client.upload(image: Self.image, deleteHash: nil) { link, deleteHash, error in
            XCTAssertNil(error)
            XCTAssertEqual(link, "https://i.imgur.com/avatar.jpg")
            XCTAssertEqual(deleteHash, "delete-me")
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
    }

    func testSuccessWithoutDeleteHashReturnsNilHash() {
        let expected = expectation(description: "upload succeeds without delete hash")
        let body = Data(#"{"success":true,"data":{"link":"https://i.imgur.com/avatar.jpg"}}"#.utf8)
        let client = makeClient { _, _ in .networkResponse(200, body) }

        let task = client.upload(image: Self.image, deleteHash: nil) { link, deleteHash, error in
            XCTAssertNil(error)
            XCTAssertEqual(link, "https://i.imgur.com/avatar.jpg")
            XCTAssertNil(deleteHash)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
    }

    func testAPIFailureReturnsError() {
        let expected = expectation(description: "API failure")
        let recorder = Recorder()
        let client = makeClient(recorder: recorder) { _, _ in
            .networkResponse(200, Data(#"{"success":false}"#.utf8))
        }

        let task = client.upload(image: Self.image, deleteHash: nil) { link, deleteHash, error in
            XCTAssertNil(link)
            XCTAssertNil(deleteHash)
            XCTAssertNotNil(error)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 1)
    }

    func testNon2xxUploadReturnsError() {
        let expected = expectation(description: "status failure")
        let client = makeClient { _, _ in .networkResponse(503, Data()) }

        let task = client.upload(image: Self.image, deleteHash: nil) { _, _, error in
            XCTAssertNotNil(error)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
    }

    func testTransportFailureReturnsError() {
        let expected = expectation(description: "transport failure")
        let client = makeClient { _, _ in
            .networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        }

        let task = client.upload(image: Self.image, deleteHash: nil) { _, _, error in
            XCTAssertNotNil(error)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
    }

    func testDeleteRetriesThreeTimesThenUploads() {
        let expected = expectation(description: "upload follows exhausted delete")
        let recorder = Recorder()
        let client = makeClient(recorder: recorder) { target, _ in
            switch target {
            case .delete:
                return .networkResponse(503, Data())
            case .upload:
                return .networkResponse(200, Self.successBody)
            }
        }

        let task = client.upload(image: Self.image, deleteHash: "old-hash") { _, _, error in
            XCTAssertNil(error)
            expected.fulfill()
        }

        withExtendedLifetime(task) {
            wait(for: [expected], timeout: 2)
        }
        XCTAssertEqual(recorder.targets.filter(\.isDelete).count, 4)
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 1)
        XCTAssertEqual(
            recorder.targets.map(\.requestKind),
            [.delete, .delete, .delete, .delete, .upload])
    }

    func testManualRetryStartsASecondUpload() {
        let first = expectation(description: "first upload fails")
        let second = expectation(description: "second upload succeeds")
        let recorder = Recorder()
        let client = makeClient(recorder: recorder) { target, requestIndex in
            guard case .upload = target else { return .networkResponse(204, Data()) }
            return requestIndex == 0
                ? .networkResponse(200, Data(#"{"success":false}"#.utf8))
                : .networkResponse(200, Self.successBody)
        }

        let firstTask = client.upload(image: Self.image, deleteHash: nil) { _, _, error in
            XCTAssertNotNil(error)
            first.fulfill()
        }
        withExtendedLifetime(firstTask) {
            wait(for: [first], timeout: 2)
        }

        let secondTask = client.upload(image: Self.image, deleteHash: nil) { _, _, error in
            XCTAssertNil(error)
            second.fulfill()
        }
        withExtendedLifetime(secondTask) {
            wait(for: [second], timeout: 2)
        }
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 2)
    }

    func testModelManualRetryRestartsWholeCycleAndMutatesStateOnMain() {
        let firstFailure = expectation(description: "model reaches error")
        let retrySuccess = expectation(description: "model reaches success")
        let recorder = Recorder()
        let client = makeClient(recorder: recorder) { target, _ in
            guard case .upload = target else { return .networkResponse(204, Data()) }
            let uploadNumber = recorder.targets.filter(\.isUpload).count
            return uploadNumber == 1
                ? .networkResponse(200, Data(#"{"success":false}"#.utf8))
                : .networkResponse(200, Self.successBody)
        }
        DWAvatarUploadClient.testingHTTPClient = client.httpClientForTesting
        UserDefaults.standard.set("old-hash", forKey: "ImgurImageDeleteHash")

        let model = DWUploadAvatarModel(image: Self.image)
        var observation: NSKeyValueObservation?
        observation = model.observe(\.state, options: [.new]) { observed, _ in
            XCTAssertTrue(Thread.isMainThread)
            if observed.state == .error {
                firstFailure.fulfill()
            } else if observed.state == .success {
                retrySuccess.fulfill()
            }
        }

        wait(for: [firstFailure], timeout: 2)
        model.retry()
        wait(for: [retrySuccess], timeout: 2)
        XCTAssertEqual(model.resultURLString, "https://i.imgur.com/avatar.jpg")
        XCTAssertEqual(recorder.targets.filter(\.isDelete).count, 2)
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 2)
        withExtendedLifetime(observation) {}
    }

    func testModelSuccessWithoutDeleteHashClearsStoredHash() {
        let success = expectation(description: "model succeeds")
        let body = Data(#"{"success":true,"data":{"link":"https://i.imgur.com/avatar.jpg"}}"#.utf8)
        let client = makeClient { target, _ in
            switch target {
            case .delete:
                return .networkResponse(204, Data())
            case .upload:
                return .networkResponse(200, body)
            }
        }
        DWAvatarUploadClient.testingHTTPClient = client.httpClientForTesting
        UserDefaults.standard.set("old-hash", forKey: "ImgurImageDeleteHash")

        let model = DWUploadAvatarModel(image: Self.image)
        var observation: NSKeyValueObservation?
        observation = model.observe(\.state, options: [.new]) { observed, _ in
            if observed.state == .success {
                success.fulfill()
            }
        }

        wait(for: [success], timeout: 2)
        XCTAssertNil(UserDefaults.standard.string(forKey: "ImgurImageDeleteHash"))
        withExtendedLifetime(observation) {}
    }

    func testCancelBeforeRequestSuppressesCompletion() {
        let completion = expectation(description: "completion is suppressed")
        completion.isInverted = true
        let recorder = Recorder()
        let imageQueue = DispatchQueue(label: "avatar-test.suspended")
        imageQueue.suspend()
        let client = makeClient(recorder: recorder, imageQueue: imageQueue) { _, _ in
            .networkResponse(200, Self.successBody)
        }

        let task = client.upload(image: Self.image, deleteHash: nil) { _, _, _ in
            completion.fulfill()
        }
        task.cancel()
        imageQueue.resume()

        wait(for: [completion], timeout: 0.3)
        XCTAssertTrue(recorder.targets.isEmpty)
    }

    func testCancelDuringDeleteSuppressesUploadAndCompletion() {
        let deleteStarted = expectation(description: "delete starts")
        let completion = expectation(description: "completion is suppressed")
        completion.isInverted = true
        let recorder = Recorder()
        recorder.onRequest = { target in
            if case .delete = target { deleteStarted.fulfill() }
        }
        let client = makeClient(recorder: recorder, stub: .delayed(seconds: 1.0)) { target, _ in
            switch target {
            case .delete: return .networkResponse(204, Data())
            case .upload: return .networkResponse(200, Self.successBody)
            }
        }

        let task = client.upload(image: Self.image, deleteHash: "old-hash") { _, _, _ in
            completion.fulfill()
        }
        wait(for: [deleteStarted], timeout: 1)
        task.cancel()

        wait(for: [completion], timeout: 0.4)
        XCTAssertEqual(recorder.targets.filter(\.isDelete).count, 1)
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 0)
    }

    func testCancelDuringUploadSuppressesLateStateMutation() {
        let uploadStarted = expectation(description: "upload starts")
        let completion = expectation(description: "completion is suppressed")
        completion.isInverted = true
        let recorder = Recorder()
        recorder.onRequest = { target in
            if case .upload = target { uploadStarted.fulfill() }
        }
        let client = makeClient(recorder: recorder, stub: .delayed(seconds: 1.0)) { _, _ in
            .networkResponse(200, Self.successBody)
        }

        let task = client.upload(image: Self.image, deleteHash: nil) { _, _, _ in
            completion.fulfill()
        }
        wait(for: [uploadStarted], timeout: 1)
        task.cancel()

        wait(for: [completion], timeout: 0.4)
        XCTAssertEqual(recorder.targets.filter(\.isUpload).count, 1)
    }

    func testModelCancelDuringUploadPreventsLateStateMutation() {
        let uploadStarted = expectation(description: "model upload starts")
        let recorder = Recorder()
        recorder.onRequest = { target in
            if case .upload = target { uploadStarted.fulfill() }
        }
        let client = makeClient(recorder: recorder, stub: .delayed(seconds: 1.0)) { _, _ in
            .networkResponse(200, Self.successBody)
        }
        DWAvatarUploadClient.testingHTTPClient = client.httpClientForTesting

        let model = DWUploadAvatarModel(image: Self.image)
        wait(for: [uploadStarted], timeout: 1)
        model.cancel()

        let settled = expectation(description: "late callback window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.resultURLString)
    }

    private func makeClient(
        recorder: Recorder = Recorder(),
        imageQueue: DispatchQueue = DispatchQueue(label: "avatar-test.image"),
        stub: Moya.StubBehavior = .immediate,
        response: @escaping (DWAvatarEndpoint, Int) -> Sample
    ) -> DWAvatarUploadClient {
        let endpointClosure: (DWAvatarEndpoint) -> Endpoint = { target in
            recorder.append(target)
            let requestIndex = recorder.targets.count - 1
            return Endpoint(
                url: target.baseURL.appendingPathComponent(target.path).absoluteString,
                sampleResponseClosure: { response(target, requestIndex) },
                method: target.method,
                task: target.task,
                httpHeaderFields: target.headers)
        }
        let provider = MoyaProvider<DWAvatarEndpoint>(
            endpointClosure: endpointClosure,
            stubClosure: { _ in stub })
        return DWAvatarUploadClient(
            httpClient: HTTPClient(provider: provider),
            imageQueue: imageQueue)
    }

    private static var image: UIImage {
        image(size: CGSize(width: 32, height: 32))
    }

    private static func image(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.blue.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static let successBody = Data(
        #"{"success":true,"data":{"link":"https://i.imgur.com/avatar.jpg","deletehash":"delete-me"}}"#.utf8)
}

private extension DWAvatarEndpoint {
    enum RequestKind: Equatable {
        case delete
        case upload
    }

    var requestKind: RequestKind {
        switch self {
        case .delete: return .delete
        case .upload: return .upload
        }
    }

    var isDelete: Bool {
        if case .delete = self { return true }
        return false
    }

    var isUpload: Bool {
        if case .upload = self { return true }
        return false
    }
}
