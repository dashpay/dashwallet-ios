import SwiftUI
struct SendView: View {
    var body: some View {
        VStack { Text("Send"); Text("Cancel") }
    }
    func hello() -> String { NSLocalizedString("Hello", comment: "greeting") }
    func coins(_ n: Int) -> String { String(format: NSLocalizedString("%d coins", comment: ""), n) }
    func other() -> some View { Text("Not in the lists") }
}
