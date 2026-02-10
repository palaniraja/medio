import SwiftUI
import AppKit

@main
struct MedioApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject private var updater = UpdateChecker()
    @State private var showingUpdateSheet = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .background(WindowAccessor())
                .sheet(isPresented: $showingUpdateSheet) {
                    MenuBarView(updater: updater)
                }
//                .onAppear {
//                    // Check for updates when app launches
//                    updater.checkForUpdates()
//                    
//                    // Set up observer for update availability
//                    updater.onUpdateAvailable = {
//                        showingUpdateSheet = true
//                    }
//                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    showingUpdateSheet = true
                    updater.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command])
                
                if updater.updateAvailable {
                    Button("Download Update") {
                        if let url = updater.downloadURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                
                Divider()
            }
        }
    }
}

// MARK: - Preview
struct MedioApp_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light) // Change to .dark for dark mode preview
            .environmentObject(UpdateChecker())
    }
}
