import Cocoa
import Combine

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private var cancellable: AnyCancellable?
    private weak var settingsWindow: SettingsWindowController?

    init(appState: AppState) {
        self.appState = appState
        setupMenu()
        updateIcon(.normal)

        cancellable = appState.$iconState.sink { [weak self] state in
            self?.updateIcon(state)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let configItem = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        let clearItem = NSMenuItem(title: "Clear Context", action: #selector(clearContext), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateIcon(_ state: AppState.IconState) {
        let title: String
        switch state {
        case .normal: title = "Aa"
        case .contextActive: title = "Aa+"
        case .fixing: title = "\u{231B}"
        }

        if let button = statusItem.button {
            button.title = title
            button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        }
    }

    @objc private func openSettings() {
        if let existing = settingsWindow {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = SettingsWindowController(appState: appState)
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(ConfigManager.configDir)
    }

    @objc private func clearContext() {
        appState.clearContext()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
