import Combine
import SwiftUI

@MainActor
final class ProtocolCompatibilityBannerViewModel: ObservableObject {
    @Published private(set) var snapshot: WalletProtocolCompatibility?
    private let controller: WalletProtocolCompatibilityController
    private var subscription: AnyCancellable?

    init(controller: WalletProtocolCompatibilityController) {
        self.controller = controller
        snapshot = controller.snapshot
        subscription = controller.$snapshot.sink { [weak self] in self?.snapshot = $0 }
    }

    var message: String? {
        switch snapshot?.status {
        case .checking:
            return NSLocalizedString("Checking Platform compatibility…", comment: "Protocol compatibility")
        case .unavailable:
            return NSLocalizedString("Platform compatibility could not be checked. Platform operations are paused. Core remains available.", comment: "Protocol compatibility")
        case .unsupported:
            #if TESTFLIGHT
            return NSLocalizedString("This network requires a newer version of Dash Wallet. Check for an update in TestFlight. Core remains available.", comment: "Protocol compatibility")
            #else
            return NSLocalizedString("This network requires a newer version of Dash Wallet. Check the App Store for an update. Core remains available.", comment: "Protocol compatibility")
            #endif
        case .supported, nil:
            return nil
        }
    }

    var updateURL: URL? {
        #if TESTFLIGHT
        return nil
        #else
        return URL(string: "https://apps.apple.com/app/dash-wallet/id1206647026")
        #endif
    }

    func retry() { controller.refresh() }

    /// Local snapshots only: this never requests network data. It also observes
    /// unsupported versions learned by background sync on a cloned SDK.
    func observe() async {
        while !Task.isCancelled {
            controller.sample()
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
        }
    }
}

struct ProtocolCompatibilityBanner: View {
    @StateObject private var model: ProtocolCompatibilityBannerViewModel
    @Environment(\.openURL) private var openURL

    init(controller: WalletProtocolCompatibilityController) {
        _model = StateObject(wrappedValue: ProtocolCompatibilityBannerViewModel(controller: controller))
    }

    var body: some View {
        Group {
            if let message = model.message {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        if model.snapshot?.status == .checking {
                            SwiftUI.ProgressView()
                                .accessibilityLabel(Text(NSLocalizedString("Checking Platform compatibility…", comment: "Protocol compatibility")))
                        }
                        Text(message)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.snapshot?.status == .unavailable {
                        Button(NSLocalizedString("Try again", comment: "Protocol compatibility retry")) {
                            model.retry()
                        }
                    } else if model.snapshot?.status == .unsupported, let url = model.updateURL {
                        Button(NSLocalizedString("Check for update", comment: "Protocol compatibility update")) {
                            openURL(url)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.observe() }
    }
}
