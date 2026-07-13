import SwiftUI

struct AppRootView: View {
    @Bindable var session: AppSession
    var body: some View {
        Group {
            switch session.route {
            case .login: Text("River Club Login")
            default: Text("River Club")
            }
        }
        .preferredColorScheme(.dark)
    }
}
