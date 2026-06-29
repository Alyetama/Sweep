import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 600)
                .onAppear { model.loadAppsIfNeeded() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New" — this is a single-window tool
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.reloadApps() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
