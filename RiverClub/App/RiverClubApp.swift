import Foundation
import SwiftUI

@main struct RiverClubApp: App {
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    @State private var session: AppSession?

    init() {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let initialSession: AppSession
            if arguments.contains("-uiTesting"),
               arguments.contains("-uiTestingImmediatePoker") {
                initialSession = try AppSession.uiTestingImmediate(
                    resetHistoryStore: arguments.contains("-resetHistoryStore")
                )
                if arguments.contains("-openHistory") {
                    initialSession.continueAsGuest()
                    initialSession.open(.tables)
                }
            } else {
                initialSession = try AppSession.live()
            }
            _session = State(initialValue: initialSession)
        } catch {
            _session = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    AppRootView(session: session)
                } else {
                    PersistenceStartupErrorView()
                }
            }
            .transaction { transaction in
                if isUITesting {
                    transaction.disablesAnimations = true
                }
            }
        }
    }
}

struct PersistenceStartupErrorView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.orange)
            Text("牌局数据无法打开，请重新启动应用。")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(RCTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("persistence.startupError")
    }
}
