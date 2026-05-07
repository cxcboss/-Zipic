import SwiftUI

@main
struct ZipicApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Zipic") {
            MainWindowView(state: state)
                .frame(minWidth: 1120, minHeight: 780)
        }
        .windowResizability(.contentMinSize)
    }
}
