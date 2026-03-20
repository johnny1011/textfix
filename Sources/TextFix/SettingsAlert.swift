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
    private enum Metrics {
        static let panelSize = NSSize(width: 760, height: 760)
        static let outerPadding: CGFloat = 22
        static let cardGap: CGFloat = 16
        static let headerHeight: CGFloat = 96
        static let footerHeight: CGFloat = 78
        static let contentWidth = panelSize.width - (outerPadding * 2)
        static let scrollHeight = panelSize.height - headerHeight - footerHeight - (outerPadding * 2)
        static let promptEditorHeight: CGFloat = 126
        static let rowControlWidth: CGFloat = 260
    }

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
        let openAtLogin: NSSwitch
        let showNotifications: NSSwitch
    }

    @MainActor
    private final class PanelCoordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private var didFinish = false
        var response: NSApplication.ModalResponse = .abort

        func attach(to window: NSWindow) {
            self.window = window
            window.delegate = self
        }

        @objc func save(_ sender: Any?) {
            finish(with: .alertFirstButtonReturn)
        }

        @objc func cancel(_ sender: Any?) {
            finish(with: .alertSecondButtonReturn)
        }

        func windowWillClose(_ notification: Notification) {
            finish(with: .alertSecondButtonReturn, closeWindow: false)
        }

        private func finish(with response: NSApplication.ModalResponse, closeWindow: Bool = true) {
            guard !didFinish else {
                return
            }

            didFinish = true
            self.response = response
            NSApp.stopModal(withCode: response)

            guard closeWindow else {
                return
            }

            window?.orderOut(nil)
            window?.close()
        }
    }

    func present(config: AppConfig) -> SettingsValues? {
        let (panel, controls, coordinator) = buildPanel(config: config)

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let response = NSApp.runModal(for: panel)
        if panel.isVisible {
            panel.orderOut(nil)
        }

        guard response == .alertFirstButtonReturn else {
            return nil
        }

        _ = coordinator

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

    private func buildPanel(config: AppConfig) -> (NSPanel, Controls, PanelCoordinator) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.panelSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "TextFix Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = false
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: Metrics.panelSize))
        root.material = .underWindowBackground
        root.blendingMode = .withinWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true

        let header = makeHeaderView(width: Metrics.panelSize.width)
        header.frame = NSRect(
            x: 0,
            y: Metrics.panelSize.height - Metrics.headerHeight,
            width: Metrics.panelSize.width,
            height: Metrics.headerHeight
        )
        root.addSubview(header)

        let separator = NSBox(frame: NSRect(
            x: Metrics.outerPadding,
            y: Metrics.panelSize.height - Metrics.headerHeight - 1,
            width: Metrics.panelSize.width - (Metrics.outerPadding * 2),
            height: 1
        ))
        separator.boxType = .separator
        root.addSubview(separator)

        let (contentView, controls) = buildContentView(config: config)
        let scrollView = NSScrollView(frame: NSRect(
            x: Metrics.outerPadding,
            y: Metrics.footerHeight,
            width: Metrics.contentWidth,
            height: Metrics.scrollHeight
        ))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = contentView
        root.addSubview(scrollView)

        let footer = makeFooterView(width: Metrics.panelSize.width)
        footer.frame = NSRect(x: 0, y: 0, width: Metrics.panelSize.width, height: Metrics.footerHeight)
        root.addSubview(footer)

        let coordinator = PanelCoordinator()
        coordinator.attach(to: panel)

        if let cancelButton = footer.viewWithTag(101) as? NSButton,
           let saveButton = footer.viewWithTag(102) as? NSButton {
            cancelButton.target = coordinator
            cancelButton.action = #selector(PanelCoordinator.cancel(_:))
            saveButton.target = coordinator
            saveButton.action = #selector(PanelCoordinator.save(_:))
        }

        panel.contentView = root
        return (panel, controls, coordinator)
    }

    private func buildContentView(config: AppConfig) -> (NSView, Controls) {
        let hotkeyField = HotkeyCaptureView(frame: NSRect(x: 0, y: 0, width: Metrics.rowControlWidth, height: 52))
        hotkeyField.setStringValue(config.hotkey)
        hotkeyField.setPlaceholderString("Click and press keys")

        let promptHotkeyField = HotkeyCaptureView(frame: NSRect(x: 0, y: 0, width: Metrics.rowControlWidth, height: 52))
        promptHotkeyField.setStringValue(config.promptHotkey)
        promptHotkeyField.setPlaceholderString("Click and press keys")

        let openAIField = makeSecureField(value: config.openAIAPIKey, placeholder: "sk-...")
        let anthropicField = makeSecureField(value: config.anthropicAPIKey, placeholder: "sk-ant-...")

        let modelPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: Metrics.rowControlWidth, height: 32), pullsDown: false)
        modelPopup.controlSize = .regular
        modelPopup.font = NSFont.systemFont(ofSize: 13)
        modelPopup.addItems(withTitles: modelChoices)
        if modelChoices.contains(config.model) {
            modelPopup.selectItem(withTitle: config.model)
        } else {
            modelPopup.addItem(withTitle: config.model)
            modelPopup.selectItem(withTitle: config.model)
        }

        let temperatureField = makeTextField(value: String(config.temperature), placeholder: "0.0")
        let maxTokensField = makeTextField(value: String(config.maxOutputTokens), placeholder: "512")

        let (systemPromptScroll, systemPromptView) = makePromptEditor(text: config.systemPrompt)
        let (promptPromptScroll, promptPromptView) = makePromptEditor(text: config.promptSystemPrompt)

        let openAtLoginSwitch = NSSwitch()
        openAtLoginSwitch.state = config.openAtLogin ? .on : .off

        let notificationsSwitch = NSSwitch()
        notificationsSwitch.state = config.showNotifications ? .on : .off

        let shortcutsCard = makeSectionCard(
            title: "Shortcuts",
            symbolName: "keyboard",
            rows: [
                makeInlineRow(
                    title: "Fix selection",
                    detail: "Click the shortcut capsule, then press the global key combination for correction.",
                    control: hotkeyField,
                    controlWidth: Metrics.rowControlWidth,
                    controlHeight: 52
                ),
                makeInlineRow(
                    title: "Rewrite as prompt",
                    detail: "Click the shortcut capsule, then press a separate combination for prompt-engineering mode.",
                    control: promptHotkeyField,
                    controlWidth: Metrics.rowControlWidth,
                    controlHeight: 52
                ),
            ]
        )

        let credentialsCard = makeSectionCard(
            title: "API Keys",
            symbolName: "key.horizontal",
            rows: [
                makeInlineRow(
                    title: "OpenAI",
                    detail: "Used automatically when the selected model is an OpenAI model.",
                    control: openAIField,
                    controlWidth: Metrics.rowControlWidth,
                    controlHeight: 32
                ),
                makeInlineRow(
                    title: "Anthropic",
                    detail: "Used automatically when the selected model begins with claude-.",
                    control: anthropicField,
                    controlWidth: Metrics.rowControlWidth,
                    controlHeight: 32
                ),
            ]
        )

        let modelCard = makeSectionCard(
            title: "Model & Output",
            symbolName: "slider.horizontal.3",
            rows: [
                makeInlineRow(
                    title: "Model",
                    detail: "Choose which provider and model powers each rewrite.",
                    control: modelPopup,
                    controlWidth: Metrics.rowControlWidth,
                    controlHeight: 32
                ),
                makeInlineRow(
                    title: "Temperature",
                    detail: "Lower values stay closer to the source. Higher values allow more variation.",
                    control: temperatureField,
                    controlWidth: 110,
                    controlHeight: 32
                ),
                makeInlineRow(
                    title: "Max output tokens",
                    detail: "Caps response length for both fix and prompt modes.",
                    control: maxTokensField,
                    controlWidth: 110,
                    controlHeight: 32
                ),
            ]
        )

        let promptsCard = makeSectionCard(
            title: "Prompts",
            symbolName: "text.alignleft",
            rows: [
                makeTextAreaRow(
                    title: "Fix prompt",
                    detail: "Instruction set used when correcting selected text.",
                    control: systemPromptScroll
                ),
                makeTextAreaRow(
                    title: "Prompt rewrite prompt",
                    detail: "Instruction set used when turning selected text into a stronger prompt.",
                    control: promptPromptScroll
                ),
            ]
        )

        let behaviorCard = makeSectionCard(
            title: "Behavior",
            symbolName: "switch.2",
            rows: [
                makeInlineRow(
                    title: "Open at login",
                    detail: "Launch TextFix automatically when your Mac signs in.",
                    control: openAtLoginSwitch
                ),
                makeInlineRow(
                    title: "Show notifications",
                    detail: "Display run-state updates after fixes and prompt rewrites.",
                    control: notificationsSwitch
                ),
            ]
        )

        let cards = [shortcutsCard, credentialsCard, modelCard, promptsCard, behaviorCard]
        let totalHeight = totalContentHeight(for: cards)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.contentWidth, height: totalHeight))
        var y = totalHeight - Metrics.cardGap

        for card in cards {
            let height = fittingHeight(for: card)
            card.frame = NSRect(x: 0, y: y - height, width: Metrics.contentWidth, height: height)
            contentView.addSubview(card)
            y -= height + Metrics.cardGap
        }

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
            openAtLogin: openAtLoginSwitch,
            showNotifications: notificationsSwitch
        )

        return (contentView, controls)
    }

    private func makeHeaderView(width: CGFloat) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.headerHeight))

        let badge = NSView(frame: NSRect(x: Metrics.outerPadding, y: 28, width: 46, height: 46))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor
        badge.layer?.shadowColor = NSColor.black.withAlphaComponent(0.16).cgColor
        badge.layer?.shadowOpacity = 1
        badge.layer?.shadowRadius = 12
        badge.layer?.shadowOffset = CGSize(width: 0, height: -1)

        let badgeLabel = NSTextField(labelWithString: "Aa")
        badgeLabel.frame = badge.bounds
        badgeLabel.alignment = .center
        badgeLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        badgeLabel.textColor = .white
        badge.addSubview(badgeLabel)
        container.addSubview(badge)

        let title = NSTextField(labelWithString: "TextFix Settings")
        title.frame = NSRect(x: 84, y: 50, width: width - 170, height: 24)
        title.font = NSFont.systemFont(ofSize: 23, weight: .semibold)
        title.textColor = .labelColor
        container.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "A calmer, grouped control surface inspired by Hex: compact cards, gentle contrast, and clearer settings hierarchy.")
        subtitle.frame = NSRect(x: 84, y: 22, width: width - 120, height: 36)
        subtitle.font = NSFont.systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        container.addSubview(subtitle)

        return container
    }

    private func makeFooterView(width: CGFloat) -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.footerHeight))

        let separator = NSBox(frame: NSRect(x: Metrics.outerPadding, y: Metrics.footerHeight - 1, width: width - (Metrics.outerPadding * 2), height: 1))
        separator.boxType = .separator
        footer.addSubview(separator)

        let note = NSTextField(wrappingLabelWithString: "Settings are stored locally in ~/Library/Application Support/TextFix/config.json")
        note.frame = NSRect(x: Metrics.outerPadding, y: 18, width: 360, height: 32)
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        footer.addSubview(note)

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.tag = 101
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: width - 222, y: 20, width: 96, height: 32)
        footer.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.tag = 102
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: width - 116, y: 20, width: 94, height: 32)
        footer.addSubview(saveButton)

        return footer
    }

    private func makeSectionCard(title: String, symbolName: String, rows: [NSView]) -> NSView {
        let innerWidth = Metrics.contentWidth - 36
        let card = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.contentWidth, height: 10))
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        card.layer?.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        card.layer?.shadowOpacity = 1
        card.layer?.shadowRadius = 16
        card.layer?.shadowOffset = CGSize(width: 0, height: -2)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        let header = makeSectionHeader(title: title, symbolName: symbolName)
        header.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
        content.addArrangedSubview(header)
        content.setCustomSpacing(14, after: header)

        for (index, row) in rows.enumerated() {
            row.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
            content.addArrangedSubview(row)
            if index < rows.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                divider.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                content.addArrangedSubview(divider)
            }
        }

        return card
    }

    private func makeSectionHeader(title: String, symbolName: String) -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        header.addSubview(icon)
        header.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 18),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])

        return header
    }

    private func makeInlineRow(
        title: String,
        detail: String,
        control: NSView,
        controlWidth: CGFloat? = nil,
        controlHeight: CGFloat? = nil
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = NSFont.systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controlContainer = NSView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        controlContainer.setContentHuggingPriority(.required, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(control)

        var controlConstraints = [NSLayoutConstraint]()
        if let controlWidth {
            controlConstraints.append(controlContainer.widthAnchor.constraint(equalToConstant: controlWidth))
            controlConstraints.append(control.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor))
            controlConstraints.append(control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor))
        } else {
            controlConstraints.append(control.leadingAnchor.constraint(greaterThanOrEqualTo: controlContainer.leadingAnchor))
            controlConstraints.append(control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor))
        }
        if let controlHeight {
            controlConstraints.append(control.heightAnchor.constraint(equalToConstant: controlHeight))
        }
        controlConstraints.append(contentsOf: [
            control.centerYAnchor.constraint(equalTo: controlContainer.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: controlContainer.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: controlContainer.bottomAnchor),
        ])
        NSLayoutConstraint.activate(controlConstraints)

        row.addSubview(textStack)
        row.addSubview(controlContainer)

        let minRowHeight = max(78, (controlHeight ?? 32) + 24)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: minRowHeight),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: controlContainer.leadingAnchor, constant: -20),
            controlContainer.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 18),
            controlContainer.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            controlContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            controlContainer.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 12),
            controlContainer.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -12),
            controlContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: controlHeight ?? 32),
        ])

        return row
    }

    private func makeTextAreaRow(title: String, detail: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor

        control.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(control)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 206),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            control.heightAnchor.constraint(equalToConstant: Metrics.promptEditorHeight),
        ])

        return row
    }

    private func makeSecureField(value: String, placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: Metrics.rowControlWidth, height: 32))
        field.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.placeholderString = placeholder
        field.stringValue = value
        return field
    }

    private func makeTextField(value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 110, height: 32))
        field.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.alignment = .right
        field.placeholderString = placeholder
        field.stringValue = value
        return field
    }

    private func makePromptEditor(text: String) -> (NSScrollView, NSTextView) {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: Metrics.contentWidth - 36, height: Metrics.promptEditorHeight))
        editor.string = text
        editor.font = NSFont.systemFont(ofSize: 13)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isContinuousSpellCheckingEnabled = true
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 10)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: Metrics.contentWidth - 36, height: Metrics.promptEditorHeight))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        scroll.documentView = editor

        return (scroll, editor)
    }

    private func fittingHeight(for card: NSView) -> CGFloat {
        card.frame.size.width = Metrics.contentWidth
        card.layoutSubtreeIfNeeded()
        return card.fittingSize.height
    }

    private func totalContentHeight(for cards: [NSView]) -> CGFloat {
        let bodyHeight = cards.reduce(CGFloat.zero) { partialResult, card in
            partialResult + fittingHeight(for: card)
        }
        return bodyHeight + (CGFloat(cards.count + 1) * Metrics.cardGap)
    }
}
