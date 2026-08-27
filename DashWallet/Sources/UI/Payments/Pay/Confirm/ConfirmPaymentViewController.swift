//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - ConfirmPaymentViewControllerDelegate

@objc
protocol ConfirmPaymentViewControllerDelegate: AnyObject {
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController)
    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController)
}

// MARK: - ConfirmPaymentViewController

/// The last step of an L1 send: the amount, what it costs, and the two buttons.
///
/// Drawn with `DashUIKit.BottomSheet` rather than the hand-built stack of
/// `BalanceView` + `UITableView` + `ActionButton` it used to be, so it matches
/// the confirmation the internal transfer and the non-Core send routes present.
/// Everything around the drawing is unchanged: it is still a `SheetViewController`
/// (same presentation, same content-measured detent), still reports through
/// `ConfirmPaymentViewControllerDelegate`, and `ConfirmPaymentModel` still owns
/// what the rows say and when the button turns into "Sending…".
///
/// The model predates `ObservableObject` and pushes updates through two
/// closures, so `State` below is the thin adapter between them and SwiftUI.
class ConfirmPaymentViewController: SheetViewController {
    public var delegate: ConfirmPaymentViewControllerDelegate?
    public var isSendingEnabled = true {
        didSet {
            if !oldValue && isSendingEnabled {
                model.stopPayment()
            }

            state.isSendingEnabled = isSendingEnabled
            isModalInPresentation = !isSendingEnabled
        }
    }

    internal let model: ConfirmPaymentModel

    private let state = State()

    /// Rebuilt from the model, so the detent can be re-resolved against it.
    private lazy var hostingController: UIHostingController<AnyView> = {
        let sheet = DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Confirm", comment: "Payment confirmation"),
            showBackButton: .constant(false)
        ) {
            ConfirmPaymentSheet(
                state: self.state,
                onCancel: { [weak self] in self?.cancel() },
                onConfirm: { [weak self] in self?.confirm() })
        }
        return UIHostingController(rootView: AnyView(sheet))
    }()

    convenience init(dataSource: ConfirmPaymentDataSource, fiatCurrency: String) {
        let model = ConfirmPaymentModel(dataSource: dataSource, fiatCurrency: fiatCurrency)
        self.init(model: model)
    }

    init(model: ConfirmPaymentModel) {
        self.model = model

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func update(with dataSource: ConfirmPaymentDataSource) {
        model.update(with: dataSource)
    }

    /// Measured from the SwiftUI content instead of counted in rows: the sheet
    /// is `selfSizing`, and the row count is not the only thing that moves its
    /// height — a wrapped address or Dynamic Type does too.
    override func contentViewHeight() -> CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let bottomInset = view.window?.safeAreaInsets.bottom ?? 0
        let measured = hostingController
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
        return measured + bottomInset
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // `BottomSheet` draws its own grabber; the base class turns the system
        // one on for the hand-built content it was written for.
        sheetPresentationController?.prefersGrabberVisible = false
        presentationController?.delegate = self

        configureModel()
        configureHierarchy()
    }
}

extension ConfirmPaymentViewController {
    private func configureModel() {
        reloadState()

        model.actionButtonTitleDidChange = { [weak self] in
            self?.state.actionTitle = self?.model.actionButtonTitle ?? ""
        }

        model.dataSourceDidChange = { [weak self] in
            self?.reloadState()
        }
    }

    /// Pull everything the sheet draws off the model in one pass, and re-resolve
    /// the detent — an updated payment output can add or drop a row.
    private func reloadState() {
        state.items = model.items ?? []
        state.actionTitle = model.actionButtonTitle
        // Digits only. `mainAmountString` is `formattedDashAmount`, which spells
        // the currency out — "DASH 0.02" — and the component draws the symbol.
        state.mainAmount = model.dataSource.amountToDisplay.dashAmount
            .formattedDashAmountWithoutCurrencySymbol
        state.feeDuffs = model.dataSource.feeDuffs
        state.totalDuffs = model.dataSource.totalDuffs
        state.supplementaryAmount = model.supplementaryAmountString

        if #available(iOS 16.0, *) {
            sheetPresentationController?.animateChanges {
                sheetPresentationController?.invalidateDetents()
            }
        }
    }

    private func configureHierarchy() {
        view.backgroundColor = UIColor(Color.dash.primaryBackground)

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

    private func cancel() {
        model.stopPayment()
        delegate?.confirmPaymentViewControllerDidCancel(self)
        dismiss(animated: true)
    }

    private func confirm() {
        isSendingEnabled = false
        model.confirmPayment()
        delegate?.confirmPaymentViewControllerDidConfirm(self)
    }
}

// MARK: - ConfirmPaymentViewController.State

extension ConfirmPaymentViewController {
    /// What the sheet draws, republished from `ConfirmPaymentModel`'s callbacks.
    @MainActor
    fileprivate final class State: ObservableObject {
        @Published var items: [DWTitleDetailItem] = []
        /// Present on the L1 payment path only; see `ConfirmPaymentDataSource`.
        @Published var feeDuffs: UInt64?
        @Published var totalDuffs: UInt64?
        @Published var actionTitle = ""
        @Published var mainAmount = ""
        @Published var supplementaryAmount = ""
        @Published var isSendingEnabled = true
    }
}

// MARK: UIAdaptivePresentationControllerDelegate

extension ConfirmPaymentViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        delegate?.confirmPaymentViewControllerDidCancel(self)
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        true
    }
}

// MARK: - ConfirmPaymentSheet

/// Amount, the rows that price it, and the pair of buttons.
///
/// Nothing below decides anything: the rows arrive as `DWTitleDetailItem`s the
/// model already assembled, and the confirm title is whatever the model says it
/// is right now — including its "Sending. / .. / ..." animation.
private struct ConfirmPaymentSheet: View {
    @ObservedObject var state: ConfirmPaymentViewController.State

    /// Every place a duff can occupy. A Core fee is a few hundred of them, and
    /// the component's five-place default renders that as "0" — a confirmation
    /// that names the wrong fee is worse than one that names a long number.
    private static let dashFractionDigits = 8

    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The amount string already carries its Dash symbol — it comes from
            // the same `formattedDashAmount` the balance view used — so the
            // component's own logo would draw a second one.
            DashUIKit.SwapAmountView(
                amount: state.mainAmount,
                secondaryText: state.supplementaryAmount,
                showDashLogo: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(Array(state.items.enumerated()), id: \.offset) { _, item in
                    DashUIKit.MenuItem(
                        title: item.title ?? "",
                        accessory: accessory(for: item))
                }
            }
            .modifier(MenuViewModifier())
            .padding(.top, 20)

            HStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: "Payment confirmation"),
                    isEnabled: state.isSendingEnabled,
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onCancel
                )

                DashUIKit.DashButton(
                    text: state.actionTitle,
                    isEnabled: state.isSendingEnabled,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onConfirm
                )
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    /// How a row's value is drawn.
    ///
    /// The two money rows go through `.balance`, which renders the amount with
    /// the library's own Dash symbol. Their `attributedDetail` carries one too,
    /// but as an image attachment — read back as plain text it disappears and
    /// the row shows a bare number, which is what it did.
    ///
    /// Matched by title against the model's own strings: the items arrive as an
    /// untyped list, and re-deriving the order here would be a second copy of
    /// the assembly `ConfirmPaymentModel` already does.
    private func accessory(for item: DWTitleDetailItem) -> DashUIKit.MenuItemAccessory {
        if let fee = state.feeDuffs, item.title == NSLocalizedString("Network fee", comment: "") {
            return .balance(dash: Int64(clamping: fee), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits)
        }
        if let total = state.totalDuffs, item.title == NSLocalizedString("Total", comment: "") {
            return .balance(dash: Int64(clamping: total), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits)
        }
        return .text(detail(of: item))
    }

    /// The row's value as plain text, shortened when the model asked for one
    /// truncated line — an address, which otherwise wraps and pushes the whole
    /// row out of shape. `MenuItem` takes a string rather than a styled view, so
    /// the shortening happens here instead of as a truncation mode.
    private func detail(of item: DWTitleDetailItem) -> String {
        let value = item.plainDetail ?? item.attributedDetail?.string ?? ""
        guard item.style == .truncatedSingleLine, value.count > 24 else { return value }
        return "\(value.prefix(12))…\(value.suffix(12))"
    }
}
