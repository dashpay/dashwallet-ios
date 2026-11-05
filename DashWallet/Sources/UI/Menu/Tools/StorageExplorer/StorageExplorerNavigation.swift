//
//  StorageExplorerNavigation.swift
//  DashWallet
//

import DashUIKit
import SwiftData
import SwiftUI
import UIKit

/// Pushes Storage Explorer pages onto the app's UIKit navigation stack, so
/// every page keeps `BaseNavigationController`'s swipe-back while drawing the
/// DashUIKit bar instead of the system one. Each pushed page gets this
/// navigator and the SwiftData container its `@Query`s read from.
final class StorageExplorerNavigator {
    private weak var navigationController: UINavigationController?
    private let container: ModelContainer?

    init(navigationController: UINavigationController, container: ModelContainer?) {
        self.navigationController = navigationController
        self.container = container
    }

    /// The hosting controller for a Storage Explorer page, with this
    /// navigator and the model container in its environment.
    func hostingController<Page: View>(for page: Page) -> UIViewController {
        let page = page.environment(\.storageExplorerNavigator, self)
        let hosting: UIViewController
        if let container {
            hosting = UIHostingController(rootView: page.modelContainer(container))
        } else {
            hosting = UIHostingController(rootView: page)
        }
        hosting.hidesBottomBarWhenPushed = true
        return hosting
    }

    func push<Page: View>(_ page: Page) {
        navigationController?.pushViewController(hostingController(for: page), animated: true)
    }

    func pop() {
        navigationController?.popViewController(animated: true)
    }
}

private struct StorageExplorerNavigatorKey: EnvironmentKey {
    static let defaultValue: StorageExplorerNavigator? = nil
}

extension EnvironmentValues {
    var storageExplorerNavigator: StorageExplorerNavigator? {
        get { self[StorageExplorerNavigatorKey.self] }
        set { self[StorageExplorerNavigatorKey.self] = newValue }
    }
}

/// A list row that pushes `destination` through the environment's
/// `StorageExplorerNavigator`, drawn with a disclosure chevron.
struct StorageExplorerLink<Destination: View, Label: View>: View {
    @Environment(\.storageExplorerNavigator) private var navigator

    private let destination: Destination
    private let label: Label

    init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        Button {
            navigator?.push(destination)
        } label: {
            ListDisclosureRow { label }
                .foregroundColor(.primary)
        }
    }
}

/// The page chrome every Storage Explorer page shares: the system bar
/// hidden, and a DashUIKit bar with a back circle that pops the page.
private struct StorageExplorerPage<Trailing: View>: ViewModifier {
    @Environment(\.storageExplorerNavigator) private var navigator

    let title: String
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: {
                        DashUIKit.NavigationBarElement.back.button { navigator?.pop() }
                    },
                    central: {
                        Text(title)
                            .dashFont(.subheadMedium)
                            .foregroundColor(.dash.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 64)
                    },
                    trailing: { trailing })
                    .background(Color(UIColor.systemGroupedBackground))
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
    }
}

extension View {
    func storageExplorerPage(_ title: String) -> some View {
        modifier(StorageExplorerPage(title: title, trailing: EmptyView()))
    }

    func storageExplorerPage<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(StorageExplorerPage(title: title, trailing: trailing()))
    }
}

/// The bar's refresh circle, disabled (and dimmed by DashUIKit) while
/// `isRefreshing`.
struct StorageExplorerRefreshButton: View {
    let accessibilityLabel: String
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        DashUIKit.NavigationBarCircleButton(
            .system("arrow.clockwise"),
            accessibilityLabel: Text(accessibilityLabel),
            action: action)
            .disabled(isRefreshing)
    }
}
