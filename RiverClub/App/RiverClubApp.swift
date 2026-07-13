import SwiftUI

@main struct RiverClubApp: App {
    @State private var session = AppSession()
    var body: some Scene { WindowGroup { AppRootView(session: session) } }
}
