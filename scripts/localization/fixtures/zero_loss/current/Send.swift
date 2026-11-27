import SwiftUI
struct SendView: View {
    var body: some View { Text("Send") }
    func coins(_ n: Int) -> String { String(localized: "\(n) coins") }
    func items(_ n: Int) -> String { String(localized: "Sample \(n) items") }
}
