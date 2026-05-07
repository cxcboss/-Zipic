import SwiftUI

@main
struct ZipicApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(AppStrings.appName) {
            MainWindowView(state: state)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 960, height: 690)
        .windowResizability(.contentMinSize)
    }
}
