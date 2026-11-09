//
//  CoreCoinConsolidationSheet.swift
//  DashWallet
//
//  The one explanation every Core-funded asset-lock route shows when the lock
//  would need more inputs than the network accepts in one transfer
//  (`AssetLockInputPolicy`), whether the app's pre-check or the SDK refused
//  it. Offers to combine the coins; the user then retries the transfer
//  themselves. The stage machine lives in `CoreCoinConsolidationViewModel`.
//

import DashUIKit
import SwiftUI

struct CoreCoinConsolidationSheet: View {

    @StateObject private var viewModel: CoreCoinConsolidationViewModel
    var onClose: () -> Void

    init(check: AssetLockInputLimit.Check, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CoreCoinConsolidationViewModel(check: check))
        self.onClose = onClose
    }

    var body: some View {
        DashUIKit.BottomSheet(
            title: AssetLockInputLimit.title,
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!viewModel.isInFlight),
            // Supplying `onClose` makes the close button live regardless of
            // `isDismissalEnabled`, so the in-flight stage has to gate it here.
            isCloseButtonEnabled: !viewModel.isInFlight,
            onClose: onClose
        ) {
            switch viewModel.stage {
            case .explain(let combineFeeDuffs):
                explainBody(combineFeeDuffs: combineFeeDuffs)
            case .combining:
                combiningBody
            case .done(let transferFits):
                doneBody(transferFits: transferFits)
            case .failed(let message):
                failedBody(message: message)
            }
        }
    }

    private func explainBody(combineFeeDuffs: UInt64?) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundColor(.dash.blue)
                .padding(.top, 24)

            message(combineFeeDuffs != nil ? AssetLockInputLimit.message : CoreCoinConsolidationViewModel.cannotCombineMessage)

            if let combineFeeDuffs {
                Text(CoreCoinConsolidationViewModel.feeLine(duffs: combineFeeDuffs))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            if combineFeeDuffs != nil {
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: CoreCoinConsolidationViewModel.combineButtonTitle,
                    positiveButtonAction: combine,
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onClose)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                closeButton
            }
        }
    }

    private var combiningBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShieldedTransferStepList(
                labels: [CoreCoinConsolidationViewModel.combiningLabel],
                currentIndex: 0)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private func doneBody(transferFits: Bool) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            message(transferFits
                ? CoreCoinConsolidationViewModel.doneMessage
                : CoreCoinConsolidationViewModel.doneShortMessage)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onClose)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func failedBody(message text: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundColor(.orange)
                .padding(.top, 24)

            message(text)

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Try again", comment: ""),
                positiveButtonAction: combine,
                negativeButtonText: NSLocalizedString("Close", comment: ""),
                negativeButtonAction: onClose)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(.dash.primaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 16)
    }

    private var closeButton: some View {
        DashButton(
            text: NSLocalizedString("Close", comment: ""),
            style: .filled,
            stretch: true,
            action: onClose)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }

    private func combine() {
        Task { await viewModel.combine() }
    }
}

extension View {
    /// Presents `CoreCoinConsolidationSheet` for `check` while it is set; the
    /// sheet's close clears it and then runs `onClose`.
    func coreCoinConsolidationSheet(
        check: Binding<AssetLockInputLimit.Check?>,
        onClose: @escaping () -> Void = {}
    ) -> some View {
        sheet(
            isPresented: Binding(get: { check.wrappedValue != nil }, set: { if !$0 { check.wrappedValue = nil } }),
            onDismiss: onClose
        ) {
            if let value = check.wrappedValue {
                CoreCoinConsolidationSheet(check: value) { check.wrappedValue = nil }
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

#if DEBUG
extension CoreCoinConsolidationSheet {

    /// Preview-only: inject a model already parked at a given stage.
    init(previewViewModel: CoreCoinConsolidationViewModel) {
        _viewModel = StateObject(wrappedValue: previewViewModel)
        onClose = { }
    }
}

#Preview("Explain") {
    CoreCoinConsolidationSheet(previewViewModel: .preview(stage: .explain(combineFeeDuffs: 22_278)))
}

#Preview("Explain — nothing to combine") {
    CoreCoinConsolidationSheet(previewViewModel: .preview(stage: .explain(combineFeeDuffs: nil)))
}

#Preview("Combining") {
    CoreCoinConsolidationSheet(previewViewModel: .preview(stage: .combining))
}

#Preview("Done") {
    CoreCoinConsolidationSheet(previewViewModel: .preview(stage: .done(transferFits: true)))
}

#Preview("Done — amount too large now") {
    CoreCoinConsolidationSheet(previewViewModel: .preview(stage: .done(transferFits: false)))
}

#Preview("Failed") {
    CoreCoinConsolidationSheet(
        previewViewModel: .preview(stage: .failed("Couldn't combine your coins. Please try again.")))
}
#endif
