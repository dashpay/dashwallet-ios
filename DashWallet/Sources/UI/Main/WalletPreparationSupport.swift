import MessageUI
import SwiftUI

@MainActor
final class WalletPreparationSupportViewModel: ObservableObject {
    struct Draft: Identifiable {
        let id = UUID()
        let recipient: String
        let subject: String
        let body: String
        let report: String?
        let useMail: Bool

        var activityItems: [Any] {
            [SupportRecipientActivityItem(email: recipient, subject: subject),
             body + (report.map { "\n\n" + $0 } ?? "")]
        }
    }

    @Published var includeDiagnostics = false
    @Published var draft: Draft?
    @Published var showError = false
    let report: String
    let recipient: String
    private let kind: WalletPreparationFailure.Kind

    init(failure: WalletPreparationFailure, bundle: Bundle = .main) {
        kind = failure.kind
        recipient = bundle.object(forInfoDictionaryKey: "SupportEmail") as? String ?? ""
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        report = failure.diagnosticReport(
            appVersion: "\(version) (\(build))",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
    }

    /// The sheet's first line: what to do, phrased for the failure at hand.
    var guidance: String {
        if kind == .legacyMigration {
            return NSLocalizedString(
                "Do not delete the app. Try moving your wallet again, or contact support if the problem continues.",
                comment: "Wallet preparation help")
        }
        return NSLocalizedString(
            "Do not delete the app. Try opening your wallet again, or contact support if the problem continues.",
            comment: "Wallet preparation help")
    }

    func prepareDraft() {
        guard !recipient.isEmpty else {
            showError = true
            return
        }
        let subject: String
        let body: String
        if kind == .legacyMigration {
            subject = "Dash Wallet — unable to move wallet"
            body = String(format: NSLocalizedString(
                "To: %@\n\nI couldn't move my wallet from the previous version of the app.\n\nWhat happened before the error:\n",
                comment: "Editable wallet support message"), recipient)
        } else {
            subject = "Dash Wallet — unable to open wallet"
            body = String(format: NSLocalizedString(
                "To: %@\n\nI couldn't open my wallet.\n\nWhat happened before the error:\n",
                comment: "Editable wallet support message"), recipient)
        }
        draft = Draft(
            recipient: recipient,
            subject: subject,
            body: body,
            report: includeDiagnostics ? report : nil,
            useMail: MFMailComposeViewController.canSendMail())
    }

    func finishMail(failed: Bool) {
        draft = nil
        showError = failed
    }
}

/// Deliberately does not use the general support log exporter. Database errors
/// may contain stored values, so this flow shares only the previewed report.
struct WalletPreparationSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WalletPreparationSupportViewModel

    init(failure: WalletPreparationFailure) {
        _viewModel = StateObject(wrappedValue: WalletPreparationSupportViewModel(failure: failure))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewModel.guidance)
                    Text("Never share your recovery phrase or private keys with anyone, including support.")
                    if !viewModel.recipient.isEmpty {
                        Text(viewModel.recipient).textSelection(.enabled)
                    }
                }
                Section {
                    Toggle("Include diagnostic report", isOn: $viewModel.includeDiagnostics)
                    DisclosureGroup("Preview diagnostic report") {
                        Text(viewModel.report)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Only the app and system versions, time and error codes. No wallet data, keys or full logs. Nothing is sent automatically.")
                }
                Section {
                    Button("Contact Support") { viewModel.prepareDraft() }
                } footer: {
                    Text("Review and send the message in your mail app, or choose a sharing option.")
                }
            }
            .navigationTitle(Text("Help"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $viewModel.draft) { draft in
                if draft.useMail {
                    WalletPreparationMailView(draft: draft, onFinish: viewModel.finishMail)
                } else {
                    ActivityView(activityItems: draft.activityItems)
                }
            }
            .alert("Couldn't prepare the support message", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try again or copy the support address and write to us from your mail app.")
            }
        }
    }
}

/// Presentation adapter only; the user controls Send, Save and Cancel.
private struct WalletPreparationMailView: UIViewControllerRepresentable {
    let draft: WalletPreparationSupportViewModel.Draft
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([draft.recipient])
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        if let report = draft.report {
            composer.addAttachmentData(Data(report.utf8), mimeType: "text/plain", fileName: "wallet-diagnostic.txt")
        }
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .failed || error != nil)
        }
    }
}
