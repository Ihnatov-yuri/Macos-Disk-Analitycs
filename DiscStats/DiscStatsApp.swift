import SwiftUI

@main
struct DiscStatsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
        }

        Window("About DiscStats", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About DiscStats") {
            openWindow(id: "about")
        }
    }
}
