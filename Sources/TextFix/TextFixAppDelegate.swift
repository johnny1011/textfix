import AppKit
@preconcurrency import ApplicationServices
import TextFixKit

final class TextFixAppDelegate: NSObject, NSApplicationDelegate {
    private struct ActionText: Sendable {
        let inProgressTitle: String
        let successTitle: String
    }

    private struct EventAccessStatus {
        let canListen: Bool
        let canPost: Bool

        var isReadyForHotkeys: Bool {
            canListen
        }

        var isReadyForAction: Bool {
            canPost
        }
    }

    private let configStore = ConfigStore()
    private let apiClient = APIClient()
    private let notificationManager = NotificationManager()
    private let keyboardController = KeyboardController()
    private let hotkeyManager = HotkeyManager()
    private let settingsAlert = SettingsAlert()
    private let runSemaphore = DispatchSemaphore(value: 1)
    private let configQueue = DispatchQueue(label: "TextFix.Config")

    private var config: AppConfig
    private var statusItem: NSStatusItem?

    override init() {
        config = configStore.load()
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        hotkeyManager.onFixHotkey = {
            Task { @MainActor in
                NSApp.sendAction(#selector(TextFixAppDelegate.fixSelectionClicked(_:)), to: NSApp.delegate, from: nil)
            }
        }
        hotkeyManager.onPromptHotkey = {
            Task { @MainActor in
                NSApp.sendAction(#selector(TextFixAppDelegate.rewritePromptClicked(_:)), to: NSApp.delegate, from: nil)
            }
        }
        hotkeyManager.updateHotkeys(
            fix: HotkeySupport.parse(currentConfig().hotkey) ?? HotkeySupport.parse(AppConfig.defaultConfig.hotkey),
            prompt: HotkeySupport.parse(currentConfig().promptHotkey) ?? HotkeySupport.parse(AppConfig.defaultConfig.promptHotkey)
        )
        ensureAccessibility()
        let eventAccess = requestEventAccessIfNeeded()
        if !eventAccess.isReadyForHotkeys || !hotkeyManager.start() {
            showEventAccessAlert(status: eventAccess, reason: .hotkeys)
        }
        applyLoginItem(enabled: currentConfig().openAtLogin)
    }

    @MainActor
    @objc private func fixSelectionClicked(_ sender: Any?) {
        runAction(mode: .fix)
    }

    @MainActor
    @objc private func rewritePromptClicked(_ sender: Any?) {
        runAction(mode: .prompt)
    }

    @MainActor
    @objc private func settingsClicked(_ sender: Any?) {
        openSettings()
    }

    @MainActor
    @objc private func openConfigFolderClicked(_ sender: Any?) {
        do {
            try configStore.ensureConfigDirectory()
        } catch {
            showAlert(title: "Unable to open config folder", message: error.localizedDescription)
            return
        }
        NSWorkspace.shared.open(configStore.configDirectoryURL)
    }

    @MainActor
    @objc private func quitClicked(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @MainActor
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Aa"
        item.button?.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let menu = NSMenu()
        menu.addItem(withTitle: "Fix Selection", action: #selector(fixSelectionClicked(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rewrite as Better Prompt", action: #selector(rewritePromptClicked(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(settingsClicked(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open Config Folder", action: #selector(openConfigFolderClicked(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitClicked(_:)), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem = item
        statusItem?.menu = menu
    }

    @MainActor
    private func runAction(mode: ActionMode) {
        let eventAccess = requestEventAccessIfNeeded()
        guard eventAccess.isReadyForAction else {
            showEventAccessAlert(status: eventAccess, reason: .textReplacement)
            return
        }

        let config = currentConfig()
        let provider = config.provider
        guard !config.apiKey(for: provider).isEmpty else {
            promptForAPIKey(provider: provider)
            return
        }

        guard runSemaphore.wait(timeout: .now()) == .success else {
            notify(title: "Already running", message: "Please wait for the current request.")
            return
        }

        let actionText = actionText(for: mode)
        let apiClient = self.apiClient
        let keyboardController = self.keyboardController
        let notificationManager = self.notificationManager
        let model = config.model
        let temperature = config.temperature
        let maxOutputTokens = config.maxOutputTokens
        let systemPrompt = config.prompt(for: mode)
        let apiKey = config.apiKey(for: provider)
        let showNotifications = config.showNotifications
        let runSemaphore = self.runSemaphore

        let notify: @Sendable (String, String) -> Void = { title, message in
            guard showNotifications else {
                return
            }
            notificationManager.notify(title: title, body: message)
        }

        Task.detached(priority: .userInitiated) {
            defer { runSemaphore.signal() }

            let selectedText = keyboardController.copySelection()
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notify("No text selected", "Highlight text and try again.")
                return
            }

            let placeholder = "\(HotkeySupport.inlineSpinnerPrefix) \(selectedText)"
            keyboardController.replaceSelectionAndSelectLeft(placeholder, selectLength: placeholder.count)
            notify(actionText.inProgressTitle, "")

            let result = await apiClient.rewriteText(
                text: selectedText,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxOutputTokens: maxOutputTokens,
                provider: provider
            )

            guard !result.text.isEmpty else {
                keyboardController.replaceSelection(selectedText)
                let error = result.error
                await MainActor.run {
                    (NSApp.delegate as? TextFixAppDelegate)?.handleAPIError(provider: provider, error: error)
                }
                return
            }

            keyboardController.replaceSelection(result.text)
            notify(actionText.successTitle, "")
        }
    }

    private func actionText(for mode: ActionMode) -> ActionText {
        switch mode {
        case .fix:
            return ActionText(inProgressTitle: "Fixing text…", successTitle: "Fixed and pasted")
        case .prompt:
            return ActionText(inProgressTitle: "Improving prompt…", successTitle: "Prompt rewritten and pasted")
        }
    }

    private func currentConfig() -> AppConfig {
        configQueue.sync { config }
    }

    private func updateConfig(_ newConfig: AppConfig) {
        configQueue.sync {
            config = newConfig
        }
    }

    @MainActor
    private func openSettings() {
        let current = currentConfig()
        guard let values = settingsAlert.present(config: current) else {
            return
        }

        if !values.hotkey.isEmpty, HotkeySupport.parse(values.hotkey) == nil {
            showAlert(title: "Invalid hotkey", message: "Use format like <cmd>+<shift>+g")
            return
        }
        if !values.promptHotkey.isEmpty, HotkeySupport.parse(values.promptHotkey) == nil {
            showAlert(title: "Invalid prompt hotkey", message: "Use format like <cmd>+<alt>+g")
            return
        }

        var newConfig = current
        if !values.hotkey.isEmpty {
            newConfig.hotkey = values.hotkey
        }
        if !values.promptHotkey.isEmpty {
            newConfig.promptHotkey = values.promptHotkey
        }
        newConfig.openAIAPIKey = values.openAIAPIKey
        newConfig.anthropicAPIKey = values.anthropicAPIKey
        newConfig.model = values.model
        newConfig.temperature = Double(values.temperature) ?? current.temperature
        newConfig.maxOutputTokens = Int(values.maxOutputTokens) ?? current.maxOutputTokens
        newConfig.openAtLogin = values.openAtLogin
        newConfig.showNotifications = values.showNotifications
        if !values.systemPrompt.isEmpty {
            newConfig.systemPrompt = values.systemPrompt
        }
        if !values.promptSystemPrompt.isEmpty {
            newConfig.promptSystemPrompt = values.promptSystemPrompt
        }

        do {
            try configStore.save(newConfig)
        } catch {
            showAlert(title: "Unable to save settings", message: error.localizedDescription)
            return
        }

        updateConfig(newConfig)
        hotkeyManager.updateHotkeys(
            fix: HotkeySupport.parse(newConfig.hotkey) ?? HotkeySupport.parse(AppConfig.defaultConfig.hotkey),
            prompt: HotkeySupport.parse(newConfig.promptHotkey) ?? HotkeySupport.parse(AppConfig.defaultConfig.promptHotkey)
        )
        applyLoginItem(enabled: newConfig.openAtLogin)
    }

    private func ensureAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            notify(
                title: "Accessibility permission required",
                message: "Enable TextFix in System Settings > Privacy & Security > Accessibility, then relaunch."
            )
        }
    }

    private enum EventAccessReason {
        case hotkeys
        case textReplacement
    }

    private func requestEventAccessIfNeeded() -> EventAccessStatus {
        var canListen = CGPreflightListenEventAccess()
        var canPost = CGPreflightPostEventAccess()

        if !canListen {
            canListen = CGRequestListenEventAccess()
        }
        if !canPost {
            canPost = CGRequestPostEventAccess()
        }

        return EventAccessStatus(
            canListen: canListen || CGPreflightListenEventAccess(),
            canPost: canPost || CGPreflightPostEventAccess()
        )
    }

    @MainActor
    private func showEventAccessAlert(status: EventAccessStatus, reason: EventAccessReason) {
        let alert = NSAlert()
        alert.messageText = "Permissions required"

        var missing: [String] = []
        if !status.canListen {
            missing.append("Input Monitoring for global hotkeys")
        }
        if !status.canPost {
            missing.append("Input Monitoring/Accessibility for copy and paste automation")
        }

        let actionText: String
        switch reason {
        case .hotkeys:
            actionText = "TextFix could not start its global hotkeys."
        case .textReplacement:
            actionText = "TextFix could not send the copy/paste events needed for this action."
        }

        let permissionsText = missing.isEmpty ? "Required event permissions are missing." : missing.joined(separator: "\n")
        alert.informativeText = """
        \(actionText)

        Enable:
        \(permissionsText)

        Open System Settings > Privacy & Security, allow TextFix, then relaunch the app.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @MainActor
    private func promptForAPIKey(provider: Provider) {
        let alert = NSAlert()
        alert.messageText = "API key required"
        alert.informativeText = "Add your \(provider.displayName) API key in Settings to continue."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    @MainActor
    private func promptForAPIKeyIssue(provider: Provider, detail: String) {
        let alert = NSAlert()
        alert.messageText = "API key not accepted"
        let extra = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty {
            alert.informativeText = "The \(provider.displayName) API key was rejected. Update it in Settings."
        } else {
            alert.informativeText = "The \(provider.displayName) API key was rejected. Update it in Settings.\n\n\(extra)"
        }
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    @MainActor
    private func handleAPIError(provider: Provider, error: String) {
        let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = detail.lowercased()
        let authIndicators = ["401", "403", "unauthorized", "invalid", "api key", "x-api-key"]
        if authIndicators.contains(where: lowercased.contains) {
            promptForAPIKeyIssue(provider: provider, detail: detail)
            return
        }

        let title = detail.isEmpty ? "No response" : "Request failed"
        let message = detail.isEmpty ? "Check your API key or network and retry." : detail
        showAlert(title: title, message: message)
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func notify(title: String, message: String) {
        guard currentConfig().showNotifications else {
            return
        }
        notificationManager.notify(title: title, body: message)
    }

    private func loginItemPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.textfix.app.plist", isDirectory: false)
    }

    private func programArgumentsForLogin() -> [String] {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return ["/usr/bin/open", "-a", bundleURL.path]
        }
        return [CommandLine.arguments[0]]
    }

    @MainActor
    private func applyLoginItem(enabled: Bool) {
        let plistURL = loginItemPlistURL()
        let userIdentifier = getuid()

        if enabled {
            writeLoginItemPlist(to: plistURL)
            if !launchctl(arguments: ["bootstrap", "gui/\(userIdentifier)", plistURL.path]) {
                _ = launchctl(arguments: ["load", "-w", plistURL.path])
            }
            return
        }

        if !launchctl(arguments: ["bootout", "gui/\(userIdentifier)", plistURL.path]) {
            _ = launchctl(arguments: ["unload", "-w", plistURL.path])
        }
        try? FileManager.default.removeItem(at: plistURL)
    }

    @MainActor
    private func writeLoginItemPlist(to url: URL) {
        let plist: [String: Any] = [
            "KeepAlive": false,
            "Label": "com.textfix.app",
            "ProgramArguments": programArgumentsForLogin(),
            "RunAtLoad": true,
        ]

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: [.atomic])
        } catch {
            showAlert(title: "Unable to update login item", message: error.localizedDescription)
        }
    }

    private func launchctl(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
