import Cocoa
import os.log

let contextWaitingPrefix = "\u{1F535} "  // 🔵 + space
let fixingPrefix = "\u{231B} "           // ⌛ + space

@MainActor
final class AppState: ObservableObject {
    @Published var config: TextFixConfig
    @Published private(set) var iconState: IconState = .normal

    nonisolated(unsafe) var fixHotkeySpec: HotkeySpec?
    nonisolated(unsafe) var contextHotkeySpec: HotkeySpec?
    nonisolated(unsafe) var promptHotkeySpec: HotkeySpec?

    private var pendingFixText: String?
    private var textFieldRef: TextFieldReference?
    private var isFixing = false

    private let openaiProvider = OpenAIProvider()
    private let anthropicProvider = AnthropicProvider()

    enum IconState {
        case normal, contextActive, fixing
    }

    init() {
        self.config = ConfigManager.load()
        fixHotkeySpec = HotkeySpec.parse(config.hotkey)
            ?? HotkeySpec.parse(TextFixConfig.default.hotkey)
        contextHotkeySpec = HotkeySpec.parse(config.contextHotkey)
            ?? HotkeySpec.parse(TextFixConfig.default.contextHotkey)
        promptHotkeySpec = HotkeySpec.parse(config.promptHotkey)
            ?? HotkeySpec.parse(TextFixConfig.default.promptHotkey)
        logger.info("Config hotkey='\(self.config.hotkey, privacy: .public)' contextHotkey='\(self.config.contextHotkey, privacy: .public)' promptHotkey='\(self.config.promptHotkey, privacy: .public)'")
        if let fs = self.fixHotkeySpec { logger.info("Fix spec: keycode=\(fs.keycode) mods=\(fs.modifiers.rawValue)") }
        else { logger.info("Fix spec: nil") }
        if let cs = self.contextHotkeySpec { logger.info("Context spec: keycode=\(cs.keycode) mods=\(cs.modifiers.rawValue)") }
        else { logger.info("Context spec: nil") }
    }

    func saveConfig() {
        ConfigManager.save(config)
        fixHotkeySpec = HotkeySpec.parse(config.hotkey)
        contextHotkeySpec = HotkeySpec.parse(config.contextHotkey)
        promptHotkeySpec = HotkeySpec.parse(config.promptHotkey)
    }

    // MARK: - Fix Hotkey (Cmd+Shift+G)

    func onFixHotkey() {
        guard !isFixing else {
            showNotification(title: "Already running", message: "Please wait for the current request.")
            return
        }

        let provider = providerType(for: config.model)
        guard let apiKey = apiKey(for: provider), !apiKey.isEmpty else {
            showNotification(title: "API key required", message: "Add your API key in Settings.", force: true)
            return
        }

        Task { await fixSelection(apiKey: apiKey, provider: provider) }
    }

    private func fixSelection(apiKey: String, provider: ProviderType) async {
        isFixing = true

        // Get the focused text field for AX-based replacement
        let element = AccessibilityHelper.getFocusedTextField()

        let selectedText = await copyOnBackground()
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotification(title: "No text selected", message: "Highlight text and try again.", force: true)
            isFixing = false
            return
        }

        // Show inline ⌛ hourglass replacing the selected text
        var fixRef: TextFieldReference?
        if let element, let currentValue = AccessibilityHelper.getValue(of: element) {
            let hourglassText = fixingPrefix + selectedText
            if let range = currentValue.range(of: selectedText) {
                let newValue = currentValue.replacingCharacters(in: range, with: hourglassText)
                if AccessibilityHelper.setValue(of: element, to: newValue) {
                    fixRef = TextFieldReference(element: element, originalText: selectedText, markerPrefix: fixingPrefix)
                }
            }
        }
        if fixRef == nil {
            // Fallback: paste hourglass inline via clipboard
            ClipboardHelper.pasteText(fixingPrefix + selectedText)
        }

        iconState = .fixing

        do {
            let fixed = try await rewrite(text: selectedText, apiKey: apiKey, provider: provider)

            // Replace ⌛ + text with fixed text
            if let ref = fixRef, ref.replaceWithFixed(fixed) {
                // AX replacement succeeded
            } else {
                ClipboardHelper.pasteText(fixed)
            }
            showNotification(title: "Fixed!", message: "")
        } catch {
            // On error, restore original text
            if let ref = fixRef {
                ref.replaceWithFixed(selectedText)
            }
            showNotification(title: "Fix failed", message: error.localizedDescription, force: true)
        }

        isFixing = false
        iconState = .normal
    }

    // MARK: - Context Hotkey (Cmd+Shift+H)

    func onContextHotkey() {
        logger.info("onContextHotkey, pendingFixText=\(self.pendingFixText != nil ? "set" : "nil", privacy: .public)")
        if pendingFixText != nil {
            Task { await contextFix() }
        } else {
            Task { await markForContext() }
        }
    }

    private func markForContext() async {
        guard !isFixing else {
            logger.info("markForContext: busy")
            showNotification(title: "Busy", message: "Wait for the current fix to finish.", force: true)
            return
        }

        let element = AccessibilityHelper.getFocusedTextField()
        logger.info("markForContext: element=\(element != nil ? "found" : "nil", privacy: .public)")

        let text = await copyOnBackground()
        logger.info("markForContext: copied text length=\(text.count)")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("markForContext: empty text, aborting")
            showNotification(title: "No text selected", message: "Highlight text and try again.", force: true)
            return
        }

        pendingFixText = text

        // Insert 🔵 marker via Accessibility API
        if let element, let currentValue = AccessibilityHelper.getValue(of: element) {
            logger.info("markForContext: AX value length=\(currentValue.count)")
            let markedText = contextWaitingPrefix + text
            if let range = currentValue.range(of: text) {
                let newValue = currentValue.replacingCharacters(in: range, with: markedText)
                if AccessibilityHelper.setValue(of: element, to: newValue) {
                    logger.info("markForContext: AX marker set OK")
                    textFieldRef = TextFieldReference(
                        element: element,
                        originalText: text,
                        markerPrefix: contextWaitingPrefix
                    )
                    iconState = .contextActive
                    showNotification(
                        title: "Waiting for context",
                        message: "Select context text, then press the shortcut again.",
                        force: true
                    )
                    return
                } else {
                    logger.info("markForContext: AX setValue FAILED")
                }
            } else {
                logger.info("markForContext: text not found in AX value")
            }
        } else {
            logger.info("markForContext: AX getValue failed or element nil")
        }

        // Fallback: paste 🔵 marker via clipboard
        logger.info("markForContext: using clipboard fallback")
        ClipboardHelper.pasteText(contextWaitingPrefix + text)
        textFieldRef = nil
        iconState = .contextActive
        showNotification(
            title: "Waiting for context",
            message: "Select context text, then press the shortcut again.",
            force: true
        )
    }

    private func contextFix() async {
        logger.info("contextFix: starting")
        guard !isFixing else {
            logger.info("contextFix: busy, aborting")
            showNotification(title: "Busy", message: "Wait for the current fix to finish.", force: true)
            return
        }

        let provider = providerType(for: config.model)
        guard let apiKey = apiKey(for: provider), !apiKey.isEmpty else {
            logger.info("contextFix: no API key")
            showNotification(title: "API key required", message: "Add your API key in Settings.", force: true)
            return
        }

        let context = await copyOnBackground()
        logger.info("contextFix: context length=\(context.count)")
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("contextFix: empty context, aborting")
            showNotification(title: "No context selected", message: "Highlight context text and try again.", force: true)
            return
        }

        guard let textToFix = pendingFixText else {
            logger.info("contextFix: pendingFixText is nil")
            return
        }

        logger.info("contextFix: textToFix length=\(textToFix.count), calling API")
        pendingFixText = nil
        isFixing = true

        // Swap 🔵 → ⌛ in the text field
        if textFieldRef != nil {
            let swapped = textFieldRef!.swapMarker(to: fixingPrefix)
            logger.info("contextFix: swapMarker result=\(swapped)")
        }
        iconState = .fixing

        do {
            let fixed = try await rewrite(text: textToFix, apiKey: apiKey, provider: provider, context: context)
            logger.info("contextFix: API returned fixed length=\(fixed.count)")

            // Replace ⌛ + text with the fixed text
            if let ref = textFieldRef, ref.replaceWithFixed(fixed) {
                logger.info("contextFix: AX replacement OK")
                showNotification(title: "Fixed!", message: "", force: true)
            } else {
                logger.info("contextFix: AX replacement failed, writing to clipboard")
                ClipboardHelper.write(fixed)
                showNotification(
                    title: "Fixed! Ready to paste",
                    message: "Select the marked text and press Cmd+V.",
                    force: true
                )
            }
        } catch {
            logger.error("contextFix: API error: \(error.localizedDescription, privacy: .public)")
            // On error, restore original text
            if let ref = textFieldRef {
                ref.replaceWithFixed(textToFix)
            }
            showNotification(title: "Fix failed", message: error.localizedDescription, force: true)
        }

        textFieldRef = nil
        isFixing = false
        iconState = .normal
    }

    // MARK: - Prompt Hotkey (Cmd+Alt+J)

    func onPromptHotkey() {
        guard !isFixing else {
            showNotification(title: "Already running", message: "Please wait for the current request.")
            return
        }

        let provider = providerType(for: config.model)
        guard let apiKey = apiKey(for: provider), !apiKey.isEmpty else {
            showNotification(title: "API key required", message: "Add your API key in Settings.", force: true)
            return
        }

        Task { await rewriteAsPrompt(apiKey: apiKey, provider: provider) }
    }

    private func rewriteAsPrompt(apiKey: String, provider: ProviderType) async {
        isFixing = true

        let element = AccessibilityHelper.getFocusedTextField()

        let selectedText = await copyOnBackground()
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotification(title: "No text selected", message: "Highlight text and try again.", force: true)
            isFixing = false
            return
        }

        // Show inline ⌛ hourglass replacing the selected text
        var fixRef: TextFieldReference?
        if let element, let currentValue = AccessibilityHelper.getValue(of: element) {
            let hourglassText = fixingPrefix + selectedText
            if let range = currentValue.range(of: selectedText) {
                let newValue = currentValue.replacingCharacters(in: range, with: hourglassText)
                if AccessibilityHelper.setValue(of: element, to: newValue) {
                    fixRef = TextFieldReference(element: element, originalText: selectedText, markerPrefix: fixingPrefix)
                }
            }
        }
        if fixRef == nil {
            ClipboardHelper.pasteText(fixingPrefix + selectedText)
        }

        iconState = .fixing

        do {
            let rewritten = try await rewrite(text: selectedText, apiKey: apiKey, provider: provider, systemPrompt: config.promptSystemPrompt)

            if let ref = fixRef, ref.replaceWithFixed(rewritten) {
                // AX replacement succeeded
            } else {
                ClipboardHelper.pasteText(rewritten)
            }
            showNotification(title: "Prompt ready!", message: "")
        } catch {
            if let ref = fixRef {
                ref.replaceWithFixed(selectedText)
            }
            showNotification(title: "Rewrite failed", message: error.localizedDescription, force: true)
        }

        isFixing = false
        iconState = .normal
    }

    func clearContext() {
        let hadState = pendingFixText != nil
        if let ref = textFieldRef {
            ref.replaceWithFixed(ref.originalText)
        }
        pendingFixText = nil
        textFieldRef = nil
        iconState = .normal
        if hadState {
            showNotification(title: "Context cleared", message: "", force: true)
        } else {
            showNotification(title: "No context", message: "No context is currently stored.", force: true)
        }
    }

    // MARK: - Helpers

    func showNotification(title: String, message: String, force: Bool = false) {
        guard force || config.showNotifications else { return }
        NotificationManager.send(title: title, message: message)
    }

    private func providerType(for model: String) -> ProviderType {
        ProviderType.from(model: model)
    }

    private func apiKey(for provider: ProviderType) -> String? {
        switch provider {
        case .openai:
            let key = config.openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        case .anthropic:
            let key = config.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        }
    }

    private func rewrite(text: String, apiKey: String, provider: ProviderType, context: String? = nil, systemPrompt: String? = nil) async throws -> String {
        let p: TextFixProvider = provider == .anthropic ? anthropicProvider : openaiProvider
        return try await p.rewrite(
            text: text,
            apiKey: apiKey,
            model: config.model,
            systemPrompt: systemPrompt ?? config.systemPrompt,
            temperature: config.temperature,
            maxTokens: config.maxOutputTokens,
            context: context,
            timeout: 30
        )
    }

    private func copyOnBackground() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let text = ClipboardHelper.copySelection()
                continuation.resume(returning: text)
            }
        }
    }
}
