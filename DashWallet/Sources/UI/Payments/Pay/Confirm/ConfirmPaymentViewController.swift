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

import Combine
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
/// `ConfirmPaymentSheet` draws it with the design system's parts, as the
/// contact-payment and internal-transfer confirmations do, and observes
/// `ConfirmPaymentModel` directly: the model owns what the rows say and when the
/// button turns into "Sending…". This controller only presents the sheet (a
/// `SheetViewController`, with the detent measured from the content), and
/// reports the two buttons through `ConfirmPaymentViewControllerDelegate`.
class ConfirmPaymentViewController: SheetViewController {
    public var delegate: ConfirmPaymentViewControllerDelegate?

    public var isSendingEnabled: Bool {
        get { model.isSendingEnabled }
        set {
            if !model.isSendingEnabled && newValue {
                model.stopPayment()
            }
            model.isSendingEnabled = newValue
            isModalInPresentation = !newValue
        }
    }

    internal let model: ConfirmPaymentModel

    private var itemsObserver: AnyCancellable?

    /// Kept so the detent can be measured against it.
    private lazy var hostingController: UIHostingController<AnyView> = {
        // `BottomSheet` stores its content closure, and this controller owns
        // the hosting controller that owns the sheet — so the closure holds
        // the model and a weak controller, never `self`. A strong capture kept
        // every confirmation alive, and with it the model's exchange-rate
        // observer and its "Sending…" timer.
        let model = self.model
        let sheet = DashUIKit.BottomSheet.selfSizing(
            title: String(localized: "Confirm", comment: "Payment confirmation"),
            showBackButton: .constant(false)
        ) { [weak self] in
            ConfirmPaymentSheet(
                model: model,
                onCancel: { self?.cancel() },
                onConfirm: { self?.confirm() })
        }
        let hosting = UIHostingController(rootView: AnyView(sheet))
        // Left on, the sheet's safe areas are counted into `sizeThatFits`, so
        // the detent came out taller than the content.
        hosting.safeAreaRegions = []
        // Its own height, pinned to the top (see `configureHierarchy`):
        // stretched to the sheet, a fixed-height `BottomSheet` centres in any
        // slack, which put ~40pt of empty space above the grabber.
        hosting.sizingOptions = .intrinsicContentSize
        return hosting
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
        // No home-indicator inset added: a custom detent's height already
        // excludes the bottom safe area, and UIKit adds it on top.
        return hostingController
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // `BottomSheet` draws its own grabber; the base class turns the system
        // one on for the hand-built content it was written for.
        sheetPresentationController?.prefersGrabberVisible = false
        presentationController?.delegate = self

        observeRows()
        configureHierarchy()
    }
}

extension ConfirmPaymentViewController {
    /// Re-resolve the detent when the rows change: an updated payment output
    /// can add or drop one. Only then — the model also changes on every
    /// exchange-rate tick, which moves the fiat line but never the height, and
    /// re-resolving the detent measures the whole SwiftUI tree.
    private func observeRows() {
        itemsObserver = model.$items
            .dropFirst()
            .removeDuplicates { $0.elementsEqual($1) { $0 === $1 } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let sheet = self?.sheetPresentationController else { return }
                if #available(iOS 16.0, *) {
                    sheet.animateChanges { sheet.invalidateDetents() }
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
            hostingController.view.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
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
struct ConfirmPaymentSheet: View {
    @ObservedObject var model: ConfirmPaymentModel

    /// Every place a duff can occupy. A Core fee is a few hundred of them, and
    /// the component's five-place default renders that as "0" — a confirmation
    /// that names the wrong fee is worse than one that names a long number.
    private static let dashFractionDigits = 8

    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Digits only, so the Dash symbol is the component's own logo.
            DashUIKit.SwapAmountView(
                amount: mainAmount,
                secondaryText: model.supplementaryAmountString,
                showDashLogo: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                    if let title = item.title, !title.isEmpty {
                        DashUIKit.MenuItem(
                            title: title,
                            accessory: accessory(for: item))
                    } else {
                        untitledRow(item)
                    }
                }
            }
            .modifier(MenuViewModifier())
            .padding(.top, 20)

            HStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: String(localized: "Cancel", comment: "Payment confirmation"),
                    // Deliberately not `model.isSendingEnabled`: confirming
                    // also sets `isModalInPresentation`, so disabling Cancel
                    // too would leave a send that never resolves with no way
                    // off the sheet. Only the confirm button locks, as before.
                    isEnabled: true,
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onCancel
                )

                DashUIKit.DashButton(
                    text: model.actionButtonTitle,
                    isEnabled: model.isSendingEnabled,
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

    /// Digits only: `mainAmountString` is `formattedDashAmount`, which spells
    /// the currency out — "DASH 0.02" — and the component draws the symbol.
    private var mainAmount: String {
        model.dataSource.amountToDisplay.dashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    /// How a row's value is drawn.
    ///
    /// The two money rows go through `.balance`, which renders the amount with
    /// the library's own Dash symbol. Their `attributedDetail` carries one too,
    /// but as an image attachment — read back as plain text it disappears and
    /// the row shows a bare number.
    ///
    /// Matched by identity against the items `ConfirmPaymentModel` handed over
    /// as the fee and the total, not by title: data sources title those rows
    /// differently ("Network fee" on the L1 path, "Fee" on Uphold), and a
    /// title match that misses degrades silently into the plain-text row.
    private func accessory(for item: DWTitleDetailItem) -> DashUIKit.MenuItemAccessory {
        if let fee = model.dataSource.feeDuffs, item === model.feeItem {
            return .balance(dash: Int64(clamping: fee), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits)
        }
        if let total = model.dataSource.totalDuffs, item === model.totalItem {
            return .balance(dash: Int64(clamping: total), sign: .none,
                            maximumFractionDigits: Self.dashFractionDigits)
        }
        return .text(detail(of: item))
    }

    /// A row the model built without a title: a BIP70 merchant's name, its memo
    /// and requested-amount line, Uphold's "fee will be deducted" note.
    /// `MenuItem` would draw it as an empty label with the text squeezed into
    /// the trailing value, so it takes the full width, wraps, and keeps the
    /// alignment its data source asked for.
    private func untitledRow(_ item: DWTitleDetailItem) -> some View {
        let alignment: (text: TextAlignment, frame: Alignment)
        switch item.detailAlignment {
        case .center: alignment = (.center, .center)
        case .right: alignment = (.trailing, .trailing)
        default: alignment = (.leading, .leading)
        }
        return Text(detail(of: item))
            .dashFont(.subhead)
            .foregroundColor(Color.dash.secondaryText)
            .multilineTextAlignment(alignment.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            // `MenuItem`'s own insets, so the text lines up with the titled rows.
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    /// The row's value as plain text, shortened when the model asked for one
    /// truncated line — an address, which otherwise wraps and pushes the whole
    /// row out of shape. `MenuItem` takes a string rather than a styled view, so
    /// the shortening happens here instead of as a truncation mode.
    ///
    /// An attributed detail's image attachments (the Dash symbol) read back as
    /// U+FFFC, which renders as a visible replacement glyph, so they are dropped.
    private func detail(of item: DWTitleDetailItem) -> String {
        let value = item.plainDetail
            ?? item.attributedDetail?.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespaces)
            ?? ""
        guard item.style == .truncatedSingleLine, value.count > 24 else { return value }
        return "\(value.prefix(12))…\(value.suffix(12))"
    }
}
