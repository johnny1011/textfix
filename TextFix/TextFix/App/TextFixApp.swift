import Cocoa
import os.log

let logger = Logger(subsystem: "com.textfix.app", category: "main")

@main
enum TextFixMain {
    static func main() {
        setbuf(stdout, nil)  // Disable stdout buffering
        logger.info("TextFix starting")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var appState: AppState!
    private var hotkeyMonitor: GlobalHotkeyMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        appState = AppState()
        logger.info("AppState created")
        statusBarController = StatusBarController(appState: appState)
        logger.info("StatusBarController created")
        hotkeyMonitor = GlobalHotkeyMonitor(appState: appState)
        hotkeyMonitor.start()
        logger.info("HotkeyMonitor started")

        AccessibilityHelper.ensurePermission()
        NotificationManager.requestPermission()
        logger.info("Setup complete")
    }
}
