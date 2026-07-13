import Foundation
import SwiftUI

@main struct RiverClubApp: App {
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            AppRootView(session: session)
                .transaction { transaction in
                    if isUITesting {
                        transaction.disablesAnimations = true
                    }
                }
        }
    }
}
