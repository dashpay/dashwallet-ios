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
import Vision

#if DASHPAY

// MARK: - AvatarCropScreen

/// Crops a picked or downloaded picture to the round avatar. A downloaded
/// picture stays where it is: the crop goes into its URL. A photo from the
/// device is uploaded to Imgur, after the user agrees to Imgur's terms.
struct AvatarCropScreen: View {
    let image: UIImage
    /// Set for a picture downloaded from a public URL.
    let imageURL: URL?
    let onDone: (_ image: UIImage, _ urlString: String) -> Void
    let onCancel: () -> Void

    @StateObject private var crop = AvatarCropController()
    @State private var upload: AvatarUploadFlow?
    /// Set when the upload finished; handed over once its sheet is gone.
    @State private var uploaded: (image: UIImage, urlString: String)?

    var body: some View {
        ZStack {
            Color(white: 0.12).ignoresSafeArea()

            AvatarCropView(image: image, controller: crop)
                .ignoresSafeArea()

            // Hidden while a sheet is up, so the picture shows unobstructed.
            if upload == nil {
                VStack(spacing: 0) {
                    Text(NSLocalizedString("Move and Zoom your photo to find the perfect fit", comment: ""))
                        .font(Font(UIFont.dw_font(forTextStyle: .body)))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 38)
                        .padding(.top, 114)
                        .allowsHitTesting(false)

                    Spacer()

                    VStack(spacing: 8) {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Select", comment: ""),
                            fillsWidth: true, size: .large, style: .filledBlue,
                            action: select)
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Cancel", comment: ""),
                            fillsWidth: true, size: .large, style: .plainWhite,
                            action: onCancel)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
                }
            }
        }
        .sheet(item: $upload, onDismiss: {
            if let uploaded {
                self.uploaded = nil
                onDone(uploaded.image, uploaded.urlString)
            }
        }) { flow in
            AvatarUploadSheet(flow: flow) { image, urlString in
                uploaded = (image, urlString)
                upload = nil
            } onCancel: {
                upload = nil
            }
        }
    }

    private func select() {
        guard let result = crop.crop() else { return }
        if let imageURL {
            onDone(result.image, Self.urlString(imageURL, croppedTo: result.rectOfInterest))
        } else {
            upload = AvatarUploadFlow(image: result.image)
        }
    }

    /// The crop as fractions of the picture, in the URL:
    /// `dashpay-profile-pic-zoom=left,top,right,bottom`.
    static func urlString(_ url: URL, croppedTo rect: CGRect) -> String {
        let hasQuery = !(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).isEmpty
        let parameter = String(format: "%@%@=%f,%f,%f,%f",
                               hasQuery ? "&" : "?", DPCropParameterName,
                               rect.minX, rect.minY, rect.maxX, rect.maxY)
        return url.absoluteString + parameter
    }
}

// MARK: - Crop view

/// Owns the crop view, so the screen can read the crop when Select is tapped.
@MainActor
final class AvatarCropController: ObservableObject {
    fileprivate weak var cropView: TOCropView?

    /// The cropped picture and the crop as fractions of the whole picture.
    func crop() -> (image: UIImage, rectOfInterest: CGRect)? {
        guard let cropView else { return nil }
        let frame = cropView.imageCropFrame
        let size = cropView.image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let image = cropView.image.croppedImage(withFrame: frame, angle: cropView.angle, circularClip: false)
        let rect = CGRect(x: frame.minX / size.width, y: frame.minY / size.height,
                          width: frame.width / size.width, height: frame.height / size.height)
        return (image, rect)
    }
}

private struct AvatarCropView: UIViewRepresentable {
    let image: UIImage
    let controller: AvatarCropController

    func makeUIView(context: Context) -> CropContainerView {
        let view = CropContainerView(image: image)
        controller.cropView = view.cropView
        return view
    }

    func updateUIView(_ uiView: CropContainerView, context: Context) { }
}

/// Lays the crop view out to fill itself and starts it on the first layout
/// with a size; centres the crop on a face when one is found.
private final class CropContainerView: UIView {
    let cropView: TOCropView
    private var didSetUp = false
    private var faceRect: CGRect?

    init(image: UIImage) {
        cropView = TOCropView(croppingStyle: .circular, image: image)
        super.init(frame: .zero)
        cropView.cropViewPadding = 38
        addSubview(cropView)
        AvatarFaceDetector.detect(in: image) { [weak self] rect in
            guard let self, let rect else { return }
            self.faceRect = rect
            if self.didSetUp { self.cropView.imageCropFrame = rect }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        cropView.frame = bounds
        guard !didSetUp, bounds.width > 0, bounds.height > 0 else { return }
        didSetUp = true
        cropView.performInitialSetup()
        if let faceRect { cropView.imageCropFrame = faceRect }
    }
}

/// Finds the first face in a picture, in the picture's coordinates.
enum AvatarFaceDetector {
    static func detect(in image: UIImage, completion: @escaping @MainActor (CGRect?) -> Void) {
        guard let cgImage = image.cgImage else { return }
        let size = image.size
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            let rect = request.results?.first.map { observation -> CGRect in
                let box = observation.boundingBox
                let height = box.height * size.height
                // Vision's origin is bottom-left.
                return CGRect(x: box.minX * size.width, y: size.height * (1 - box.minY) - height,
                              width: box.width * size.width, height: height)
            }
            DispatchQueue.main.async { completion(rect) }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}

// MARK: - Upload

/// One run of the Imgur sheet: the terms first, then the upload.
final class AvatarUploadFlow: Identifiable {
    let id = UUID()
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

private struct AvatarUploadSheet: View {
    let flow: AvatarUploadFlow
    let onUploaded: (_ image: UIImage, _ urlString: String) -> Void
    let onCancel: () -> Void

    /// Created when the user agrees: nothing leaves the device before.
    @State private var model: AvatarUploadModel?

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: model == nil ? NSLocalizedString("Images Privacy Policy", comment: "") : "",
            showBackButton: .constant(false),
            onClose: cancel,
            animatesHeightChanges: true
        ) {
            Group {
                if let model {
                    AvatarUploadProgress(model: model, onUploaded: onUploaded, onCancel: cancel)
                } else {
                    terms
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onDisappear { model?.cancel() }
    }

    private var terms: some View {
        VStack(alignment: .leading, spacing: 20) {
            term(NSLocalizedString("The image you select will be uploaded to Imgur anonymously.", comment: "Don't translate 'Imgur'"))
            term(NSLocalizedString("Image uploaded can be viewed publicly by anyone.", comment: ""))
            term(NSLocalizedString("You can always delete the image uploaded, as long as you have access to this wallet.", comment: ""))

            HStack(spacing: 10) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: ""),
                    fillsWidth: true, size: .large, style: .tintedGray, action: cancel)
                DashUIKit.DashButton(
                    text: NSLocalizedString("Agree", comment: ""),
                    fillsWidth: true, size: .large, style: .filledBlue) {
                        withAnimation { model = AvatarUploadModel(image: flow.image) }
                    }
            }
            .padding(.top, 20)
        }
    }

    private func term(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image("icon_info")
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(text)
                .dashFont(.callout)
                .foregroundStyle(Color.dash.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cancel() {
        model?.cancel()
        onCancel()
    }
}

private struct AvatarUploadProgress: View {
    @ObservedObject var model: AvatarUploadModel
    let onUploaded: (_ image: UIImage, _ urlString: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: model.image)
                .resizable()
                .scaledToFill()
                .frame(width: 87, height: 87)
                .clipShape(Circle())
                .accessibilityHidden(true)

            HStack(spacing: 6) {
                if model.state == .error {
                    Image("icon_error")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                } else {
                    SwiftUI.ProgressView()
                }
                Text(model.state == .error
                     ? NSLocalizedString("Upload Error", comment: "")
                     : NSLocalizedString("Please Wait", comment: ""))
                    .dashFont(.headline)
                    .foregroundStyle(Color.dash.primaryText)
            }

            Text(subtitle)
                .dashFont(.body)
                .foregroundStyle(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                if model.state == .error, model.failureIsRetryable {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Try again", comment: ""),
                        fillsWidth: true, size: .large, style: .filledBlue, action: model.retry)
                }
                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: ""),
                    fillsWidth: true, size: .large, style: .tintedGray, action: onCancel)
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: model.state) { state in
            if state == .success, let url = model.resultURLString {
                onUploaded(model.image, url)
            }
        }
    }

    private var subtitle: String {
        switch model.state {
        case .error:
            model.failureMessage ?? NSLocalizedString("Unable to upload your picture. Please try again.", comment: "")
        case .loading, .success:
            NSLocalizedString("Uploading your picture to the network", comment: "")
        }
    }
}

#endif
