import Combine
import SwiftUI
import SwiftDashSDK

@MainActor
final class ProtocolCompatibilityBannerViewModel: ObservableObject {
    @Published private(set) var snapshot: ProtocolVersionInfo?
    private var subscription: AnyCancellable?

    init(controller: WalletProtocolCompatibilityController) {
        snapshot = controller.snapshot
        subscription = controller.$snapshot.sink { [weak self] in self?.snapshot = $0 }
    }

    var message: String? {
        guard snapshot?.newerProtocolAvailable == true else { return nil }
        #if TESTFLIGHT
        return NSLocalizedString("The network uses a newer protocol than this version of the app. Check for updates in TestFlight.", comment: "Protocol version advisory")
        #else
        return NSLocalizedString("The network uses a newer protocol than this version of the app. Check for available updates.", comment: "Protocol version advisory")
        #endif
    }

    var updateURL: URL? {
        #if TESTFLIGHT
        return nil
        #else
        return URL(string: "https://apps.apple.com/app/dash-wallet/id1206647026")
        #endif
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
                    Text(message)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = model.updateURL {
                        Button(NSLocalizedString("Check for update", comment: "Protocol version update")) {
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
    }
}
