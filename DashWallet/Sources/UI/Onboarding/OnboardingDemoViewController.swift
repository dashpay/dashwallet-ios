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

import UIKit

/// The mini wallet behind the onboarding carousel: the app's own root over
/// stub models, laid out at full screen size and scaled down into a device
/// bezel, which plays a part of the app for each page.
///
/// It stays UIKit: the demo is the real UIKit app, and its modal screens are
/// embedded here by hand, since UIKit would present them outside the scaled
/// view (see `DWDemoDelegate`).
final class OnboardingDemoViewController: UIViewController {
    /// Called with `false` while the demo plays a page's animation, and with
    /// `true` once it is done: the carousel waits for it.
    var onInteractionChange: ((Bool) -> Void)?

    private static let animationDuration: TimeInterval = 0.25
    private static let scale: CGFloat = 0.5

    private let miniWalletView = UIView()
    private let bezelImageView = UIImageView()
    private let rootController = DWDemoAppRootViewController()
    private lazy var demoNavigationController = BaseNavigationController(rootViewController: rootController)

    private weak var modalDimmingView: UIView?
    private weak var modalContainerView: UIView?
    private weak var modalPresentingController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        miniWalletView.backgroundColor = .black
        miniWalletView.clipsToBounds = true
        miniWalletView.layer.cornerRadius = 32
        view.addSubview(miniWalletView)

        bezelImageView.image = Self.bezelImageForCurrentDevice()
        bezelImageView.contentMode = .scaleAspectFit
        view.addSubview(bezelImageView)

        rootController.demoDelegate = self
        rootController.setLaunchingAsDeferredController()
        embed(demoNavigationController, in: miniWalletView)
    }

    // Before the children lay out, so the demo app lays out at its final
    // size and safe area.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // The mini wallet is laid out as a full screen, then scaled to half
        // and moved up, so the app inside lays out as on a real screen.
        let height = view.bounds.height
        let width = view.bounds.width
        let ratio = bezelImageView.image.map { $0.size.width / $0.size.height } ?? 1
        let offset = (height - height * Self.scale) / 2

        miniWalletView.transform = .identity
        miniWalletView.bounds = CGRect(x: 0, y: 0, width: min(height * ratio, width), height: height)
        miniWalletView.center = CGPoint(x: width / 2, y: height / 2)
        miniWalletView.transform = CGAffineTransform(scaleX: Self.scale, y: Self.scale).translatedBy(x: 0, y: -offset)

        bezelImageView.transform = .identity
        bezelImageView.frame = miniWalletView.frame.insetBy(dx: -14, dy: -10)
        bezelImageView.transform = Self.transform(for: UIDevice.current.orientation)

        // Scaled, the mini wallet loses the safe area its children lay out
        // by: give it the screen's back, a little lower at the top.
        var insets = view.safeAreaInsets
        insets.top += insets.bottom > 0 ? 10 : 30
        demoNavigationController.additionalSafeAreaInsets = insets
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.bezelImageView.transform = Self.transform(for: UIDevice.current.orientation)
        }
    }

    // MARK: Pages

    /// Plays the part of the app for a carousel page: the home screen, the
    /// payments screen, then the advanced security settings.
    func show(page: Int) {
        let navigation = demoNavigationController

        switch page {
        case 0:
            onInteractionChange?(false)
            navigation.popToRootViewController(animated: true)
            dismissModalController { [weak self] in self?.onInteractionChange?(true) }
            rootController.closePaymentsScreen()

        case 1:
            navigation.popToRootViewController(animated: true)
            // The payments screen arrives through `presentModalController`,
            // which hands interaction back once it is in.
            if modalPresentingController == nil {
                onInteractionChange?(false)
            }
            rootController.openPaymentsScreen()

        default:
            onInteractionChange?(false)
            dismissModalController { [weak self] in self?.onInteractionChange?(true) }
            if navigation.viewControllers.count == 1 {
                navigation.pushViewController(AdvancedSecurityHostingController.demo(), animated: true)
            }
        }
    }

    // MARK: Private

    private func embed(_ child: UIViewController, in container: UIView) {
        addChild(child)
        child.view.frame = container.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(child.view)
        child.didMove(toParent: self)
    }

    private func dismissModalController(completion: @escaping () -> Void) {
        UIView.animate(withDuration: Self.animationDuration / 2) {
            self.modalDimmingView?.alpha = 0
            self.modalContainerView?.alpha = 0
        } completion: { _ in
            self.modalDimmingView?.removeFromSuperview()
            self.modalContainerView?.removeFromSuperview()
            if let controller = self.modalPresentingController {
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
            }
            completion()
        }
    }

    private static func bezelImageForCurrentDevice() -> UIImage? {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return UIImage(named: "iphone_bezel")
        }
        let screen = UIScreen.main.bounds.size
        switch max(screen.width, screen.height) {
        case 1194: return UIImage(named: "ipad_pro_11_bezel")
        case 1366: return UIImage(named: "ipad_pro_12_bezel")
        default: return UIImage(named: "ipad_regular_bezel")
        }
    }

    private static func transform(for orientation: UIDeviceOrientation) -> CGAffineTransform {
        switch orientation {
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft: return CGAffineTransform(rotationAngle: .pi * 3 / 2)
        case .landscapeRight: return CGAffineTransform(rotationAngle: .pi / 2)
        default: return .identity
        }
    }
}

// MARK: - DWDemoDelegate

extension OnboardingDemoViewController: DWDemoDelegate {
    /// Slides a screen the demo presents up over the mini wallet, inside it.
    func presentModalController(_ controller: UIViewController, sender: UIViewController) {
        let parentView = miniWalletView

        let dimmingView = UIView(frame: parentView.bounds)
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.backgroundColor = .dw_modalDimming()
        parentView.addSubview(dimmingView)
        modalDimmingView = dimmingView

        let containerView = UIView()
        parentView.addSubview(containerView)
        modalContainerView = containerView

        embed(controller, in: containerView)
        controller.additionalSafeAreaInsets = rootController.view.safeAreaInsets
        modalPresentingController = controller

        let size = parentView.bounds.size
        containerView.frame = CGRect(x: 0, y: size.height, width: size.width, height: size.height)
        UIView.animate(withDuration: Self.animationDuration) {
            containerView.frame = CGRect(origin: .zero, size: size)
        } completion: { [weak self] _ in
            self?.onInteractionChange?(true)
        }
    }
}
