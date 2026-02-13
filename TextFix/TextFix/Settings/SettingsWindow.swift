import Cocoa
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(appState: AppState) {
        let settingsView = SettingsView(appState: appState) {
            NSApp.keyWindow?.close()
        }
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TextFix Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        self.init(window: window)
    }
}
