//
//  ReceiveScreenHostingController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWReceiveScreenHostingController)
final class ReceiveScreenHostingController: UIViewController {
    private var hostingController: UIHostingController<ReceiveScreen>!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_background()

        hostingController = UIHostingController(rootView: ReceiveScreen(vc: self))
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}
