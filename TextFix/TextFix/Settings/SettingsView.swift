import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var config: TextFixConfig
    @State private var errorMessage: String?
    var onDismiss: () -> Void

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self._config = State(initialValue: appState.config)
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Hotkeys") {
                    LabeledContent("Fix Hotkey") {
                        HotkeyCaptureField(value: $config.hotkey)
                            .frame(width: 200)
                    }
                    LabeledContent("Context Hotkey") {
                        HotkeyCaptureField(value: $config.contextHotkey)
                            .frame(width: 200)
                    }
                    LabeledContent("Prompt Hotkey") {
                        HotkeyCaptureField(value: $config.promptHotkey)
                            .frame(width: 200)
                    }
                }

                Section("API Keys") {
                    SecureField("OpenAI API Key", text: $config.openaiApiKey)
                    SecureField("Anthropic API Key", text: $config.anthropicApiKey)
                }

                Section("Model") {
                    Picker("Model", selection: $config.model) {
                        ForEach(allModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    TextField("Temperature", value: $config.temperature, format: .number)
                    TextField("Max Output Tokens", value: $config.maxOutputTokens, format: .number)
                }

                Section("Fix Prompt") {
                    TextEditor(text: $config.systemPrompt)
                        .frame(minHeight: 80)
                        .font(.body)
                }

                Section("Prompt Rewrite Instructions") {
                    TextEditor(text: $config.promptSystemPrompt)
                        .frame(minHeight: 80)
                        .font(.body)
                }

                Section {
                    Toggle("Open at Login", isOn: $config.openAtLogin)
                    Toggle("Show Notifications", isOn: $config.showNotifications)
                }
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 750)
    }

    private func save() {
        // Validate hotkeys
        guard HotkeySpec.parse(config.hotkey) != nil else {
            errorMessage = "Invalid fix hotkey. Use format like <cmd>+<shift>+g"
            return
        }
        guard HotkeySpec.parse(config.contextHotkey) != nil else {
            errorMessage = "Invalid context hotkey. Use format like <cmd>+<shift>+h"
            return
        }
        guard HotkeySpec.parse(config.promptHotkey) != nil else {
            errorMessage = "Invalid prompt hotkey. Use format like <cmd>+<alt>+j"
            return
        }
        let hotkeys = [config.hotkey, config.contextHotkey, config.promptHotkey]
        if Set(hotkeys).count != hotkeys.count {
            errorMessage = "All hotkeys must be different."
            return
        }

        appState.config = config
        appState.saveConfig()
        LoginItemManager.setEnabled(config.openAtLogin)
        onDismiss()
    }
}
