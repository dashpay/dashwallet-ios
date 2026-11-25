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

import SwiftUI

// MARK: - OnboardingPage

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let detail: String

    /// The legacy key a wallet from before the redesign left in the defaults.
    private static let legacyHasWalletKey = "BALANCE"

    static func all(defaults: UserDefaults = .standard) -> [OnboardingPage] {
        let hasWallet = defaults.object(forKey: legacyHasWalletKey) != nil
        return [
            OnboardingPage(
                id: 0,
                title: hasWallet
                    ? String(localized: "We Upgraded", comment: "")
                    : String(localized: "Welcome", comment: ""),
                detail: String(localized: "An intuitive and familiar experience across all your devices", comment: "")
            ),
            OnboardingPage(
                id: 1,
                title: String(localized: "Pay with Ease", comment: ""),
                detail: String(localized: "Pay and get paid instantly with easy to use payment flows", comment: "")
            ),
            OnboardingPage(
                id: 2,
                title: String(localized: "More Control", comment: ""),
                detail: String(localized: "Have complete control and customize your wallet based on your needs", comment: "")
            ),
        ]
    }
}

// MARK: - OnboardingViewModel

/// The carousel's page, and whether it may move: the UIKit mini wallet under
/// it plays each page's part, and holds the carousel while it does.
@MainActor
final class OnboardingViewModel: ObservableObject {
    let pages = OnboardingPage.all()

    @Published var page = 0 {
        didSet {
            if page != oldValue { onPageChange?(page) }
        }
    }
    /// Off while the mini wallet plays a page's animation.
    @Published var isInteractive = true

    var onPageChange: ((Int) -> Void)?
    var onFinish: (() -> Void)?

    var isLastPage: Bool { page == pages.count - 1 }

    func finish() {
        onFinish?()
    }
}

// MARK: - OnboardingView

/// The first-launch carousel: the page titles, dots and Skip / Get Started,
/// over the photo and the mini wallet that `OnboardingViewController` lays
/// under it.
struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                TabView(selection: $viewModel.page) {
                    ForEach(viewModel.pages) { page in
                        OnboardingPageView(page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .disabled(!viewModel.isInteractive)

                OnboardingPageIndicator(count: viewModel.pages.count, page: $viewModel.page)
                    .padding(.bottom, 8)
            }

            ZStack {
                Button(action: viewModel.finish) {
                    Text(String(localized: "Skip", comment: ""))
                        .font(.system(.body))
                        .foregroundColor(Color.dash.blue)
                        .frame(minWidth: 88, minHeight: 46)
                        .contentShape(Rectangle())
                }
                .opacity(viewModel.isLastPage ? 0 : 1)
                .accessibilityHidden(viewModel.isLastPage)

                DashButton(
                    text: String(localized: "Get Started", comment: ""),
                    style: .filledBlue,
                    size: .medium,
                    stretch: false,
                    action: viewModel.finish
                )
                .opacity(viewModel.isLastPage ? 1 : 0)
                .accessibilityHidden(!viewModel.isLastPage)
            }
            .frame(height: 46)
            .animation(.easeInOut(duration: 0.25), value: viewModel.isLastPage)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - OnboardingPageView

/// A page's title and detail, low on the page, under the mini wallet.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // The title on top, the detail centered in the rest of the
                // block, as the old page cell laid them out.
                VStack(spacing: 0) {
                    Text(page.title)
                        .scaledSystemFont(size: 34, relativeTo: .largeTitle)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(page.detail)
                        .font(.system(.body))
                        .minimumScaleFactor(0.7)
                        .frame(maxHeight: .infinity)
                }
                .foregroundColor(Color("LightTitleColor"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.17)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
        }
    }
}

// MARK: - OnboardingPageIndicator

/// The page dots; tapping one goes to its page.
private struct OnboardingPageIndicator: View {
    let count: Int
    @Binding var page: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< count, id: \.self) { index in
                // a11y-ignore: A11Y004 the dots are one adjustable element, labelled below
                Button {
                    withAnimation { page = index }
                } label: {
                    Circle()
                        .fill(index == page ? Color.dash.blue : Color("DisabledButtonColor"))
                        .frame(width: 8, height: 8)
                        .frame(width: 17.5, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Page", comment: "Onboarding page indicator, VoiceOver"))
        .accessibilityValue(String(localized: "\(page + 1) of \(count)", comment: "Onboarding page indicator, VoiceOver"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
    }
}
