import SwiftUI
struct SendView: View {
    var body: some View { Text("Send") }
    func coins(_ n: Int) -> String { String(format: NSLocalizedString("%d coins", comment: ""), n) }
    func items(_ n: Int) -> String { String(format: NSLocalizedString("Sample %d items", comment: ""), n) }
}
