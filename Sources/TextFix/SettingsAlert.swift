import AppKit
import TextFixKit

struct SettingsValues {
    let hotkey: String
    let promptHotkey: String
    let openAIAPIKey: String
    let anthropicAPIKey: String
    let model: String
    let temperature: String
    let maxOutputTokens: String
    let systemPrompt: String
    let promptSystemPrompt: String
    let openAtLogin: Bool
    let showNotifications: Bool
}

@MainActor
final class SettingsAlert {
    private struct Controls {
        let hotkey: HotkeyCaptureView
        let promptHotkey: HotkeyCaptureView
        let openAIAPIKey: NSSecureTextField
        let anthropicAPIKey: NSSecureTextField
        let model: NSPopUpButton
        let temperature: NSTextField
        let maxOutputTokens: NSTextField
        let systemPrompt: NSTextView
        let promptSystemPrompt: NSTextView
        let openAtLogin: NSButton
        let showNotifications: NSButton
    }

    func present(config: AppConfig) -> SettingsValues? {
        let alert = NSAlert()
        alert.messageText = "TextFix Settings"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let (view, controls) = buildView(config: config)
        alert.accessoryView = view

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return SettingsValues(
            hotkey: controls.hotkey.stringValue().trimmingCharacters(in: .whitespacesAndNewlines),
            promptHotkey: controls.promptHotkey.stringValue().trimmingCharacters(in: .whitespacesAndNewlines),
            openAIAPIKey: controls.openAIAPIKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            anthropicAPIKey: controls.anthropicAPIKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: controls.model.titleOfSelectedItem ?? config.model,
            temperature: controls.temperature.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            maxOutputTokens: controls.maxOutputTokens.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: controls.systemPrompt.string.trimmingCharacters(in: .whitespacesAndNewlines),
            promptSystemPrompt: controls.promptSystemPrompt.string.trimmingCharacters(in: .whitespacesAndNewlines),
            openAtLogin: controls.openAtLogin.state == .on,
            showNotifications: controls.showNotifications.state == .on
        )
    }

    private func buildView(config: AppConfig) -> (NSView, Controls) {
        let width: CGFloat = 440
        let rowHeight: CGFloat = 24
        let rowGap: CGFloat = 10
        let labelWidth: CGFloat = 170
        let inputWidth = width - labelWidth - 32
        let padding: CGFloat = 12
        let promptHeight: CGFloat = 96

        let standardRowCount: CGFloat = 7
        let toggleRowCount: CGFloat = 2
        let totalHeight =
            (padding * 2) +
            ((rowHeight + rowGap) * (standardRowCount + toggleRowCount)) +
            ((promptHeight + rowGap) * 2)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        var y = totalHeight - padding - rowHeight

        func makeLabel(_ title: String, y: CGFloat) -> NSTextField {
            let field = NSTextField(frame: NSRect(x: padding, y: y, width: labelWidth, height: rowHeight))
            field.stringValue = title
            field.isBezeled = false
            field.drawsBackground = false
            field.isEditable = false
            field.isSelectable = false
            return field
        }

        func addRow(label: String, control: NSView, height: CGFloat = rowHeight) {
            let labelField = makeLabel(label, y: y + (height == rowHeight ? 0 : height - rowHeight))
            view.addSubview(labelField)
            view.addSubview(control)
            y -= height + rowGap
        }

        let hotkeyField = HotkeyCaptureView(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        hotkeyField.setStringValue(config.hotkey)
        hotkeyField.setPlaceholderString("Click and press keys")
        addRow(label: "Fix hotkey", control: hotkeyField)

        let promptHotkeyField = HotkeyCaptureView(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        promptHotkeyField.setStringValue(config.promptHotkey)
        promptHotkeyField.setPlaceholderString("Click and press keys")
        addRow(label: "Prompt hotkey", control: promptHotkeyField)

        let openAIField = NSSecureTextField(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        openAIField.stringValue = config.openAIAPIKey
        addRow(label: "OpenAI API key", control: openAIField)

        let anthropicField = NSSecureTextField(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        anthropicField.stringValue = config.anthropicAPIKey
        addRow(label: "Anthropic API key", control: anthropicField)

        let modelPopup = NSPopUpButton(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        modelPopup.addItems(withTitles: modelChoices)
        if modelChoices.contains(config.model) {
            modelPopup.selectItem(withTitle: config.model)
        } else {
            modelPopup.addItem(withTitle: config.model)
            modelPopup.selectItem(withTitle: config.model)
        }
        addRow(label: "Model", control: modelPopup)

        let temperatureField = NSTextField(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        temperatureField.stringValue = String(config.temperature)
        addRow(label: "Temperature", control: temperatureField)

        let maxTokensField = NSTextField(frame: NSRect(x: padding + labelWidth, y: y, width: inputWidth, height: rowHeight))
        maxTokensField.stringValue = String(config.maxOutputTokens)
        addRow(label: "Max output tokens", control: maxTokensField)

        let systemPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: inputWidth, height: promptHeight))
        systemPromptView.string = config.systemPrompt
        let systemPromptScroll = NSScrollView(frame: NSRect(x: padding + labelWidth, y: y - (promptHeight - rowHeight), width: inputWidth, height: promptHeight))
        systemPromptScroll.hasVerticalScroller = true
        systemPromptScroll.borderType = .bezelBorder
        systemPromptScroll.documentView = systemPromptView
        addRow(label: "Fix prompt", control: systemPromptScroll, height: promptHeight)

        let promptPromptView = NSTextView(frame: NSRect(x: 0, y: 0, width: inputWidth, height: promptHeight))
        promptPromptView.string = config.promptSystemPrompt
        let promptPromptScroll = NSScrollView(frame: NSRect(x: padding + labelWidth, y: y - (promptHeight - rowHeight), width: inputWidth, height: promptHeight))
        promptPromptScroll.hasVerticalScroller = true
        promptPromptScroll.borderType = .bezelBorder
        promptPromptScroll.documentView = promptPromptView
        addRow(label: "Prompt rewrite prompt", control: promptPromptScroll, height: promptHeight)

        let openAtLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        openAtLoginButton.state = config.openAtLogin ? .on : .off
        openAtLoginButton.frame = NSRect(x: padding + labelWidth, y: y, width: 18, height: rowHeight)
        addRow(label: "Open at login", control: openAtLoginButton)

        let notificationsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        notificationsButton.state = config.showNotifications ? .on : .off
        notificationsButton.frame = NSRect(x: padding + labelWidth, y: y, width: 18, height: rowHeight)
        addRow(label: "Show notifications", control: notificationsButton)

        let controls = Controls(
            hotkey: hotkeyField,
            promptHotkey: promptHotkeyField,
            openAIAPIKey: openAIField,
            anthropicAPIKey: anthropicField,
            model: modelPopup,
            temperature: temperatureField,
            maxOutputTokens: maxTokensField,
            systemPrompt: systemPromptView,
            promptSystemPrompt: promptPromptView,
            openAtLogin: openAtLoginButton,
            showNotifications: notificationsButton
        )

        return (view, controls)
    }
}
