import AppKit
import TextFixKit
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    private var requestedAuthorization = false

    func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !requestedAuthorization {
            requestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else {
                    return
                }
                self.postNotification(title: title, body: body)
            }
            return
        }

        postNotification(title: title, body: body)
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

final class KeyboardController: @unchecked Sendable {
    func copySelection() -> String {
        let pasteboard = NSPasteboard.general
        let startingChangeCount = pasteboard.changeCount
        press(keyCode: HotkeySupport.keyCodeMap["c"] ?? 8, flags: .maskCommand)

        for _ in 0..<HotkeySupport.copyPollAttempts {
            usleep(HotkeySupport.copyPollInterval)
            if pasteboard.changeCount != startingChangeCount {
                break
            }
        }

        return pasteboard.string(forType: .string) ?? ""
    }

    func replaceSelection(_ text: String) {
        setClipboard(text)
        paste()
    }

    func replaceSelectionAndSelectLeft(_ text: String, selectLength: Int) {
        setClipboard(text)
        paste()
        selectLeft(count: selectLength)
    }

    private func paste() {
        press(keyCode: HotkeySupport.keyCodeMap["v"] ?? 9, flags: .maskCommand)
    }

    private func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func selectLeft(count: Int) {
        guard count > 0 else {
            return
        }

        let leftKeyCode = HotkeySupport.keyCodeMap["left"] ?? 123
        for _ in 0..<count {
            press(keyCode: leftKeyCode, flags: .maskShift)
        }
    }

    private func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return
        }
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }
}

final class HotkeyManager {
    var onFixHotkey: (@Sendable () -> Void)?
    var onPromptHotkey: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var fixSpec: HotkeySpec?
    private var promptSpec: HotkeySpec?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private enum MatchedHotkey {
        case fix
        case prompt
    }

    func updateHotkeys(fix: HotkeySpec?, prompt: HotkeySpec?) {
        lock.lock()
        defer { lock.unlock() }
        fixSpec = fix
        promptSpec = prompt
    }

    func start() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let matchedHotkey: MatchedHotkey?
        lock.lock()
        if HotkeySupport.matches(promptSpec, keyCode: keyCode, flags: flags) {
            matchedHotkey = .prompt
        } else if HotkeySupport.matches(fixSpec, keyCode: keyCode, flags: flags) {
            matchedHotkey = .fix
        } else {
            matchedHotkey = nil
        }
        lock.unlock()

        if matchedHotkey == .prompt {
            let handler = onPromptHotkey
            DispatchQueue.main.async {
                handler?()
            }
            return nil
        }

        if matchedHotkey == .fix {
            let handler = onFixHotkey
            DispatchQueue.main.async {
                handler?()
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

@MainActor
final class HotkeyCaptureView: NSView {
    private let displayField: NSTextField
    private let capsuleView: NSView
    private var storedValue = ""
    private var storedPlaceholder = ""

    override init(frame frameRect: NSRect) {
        displayField = NSTextField(frame: .zero)
        capsuleView = NSView(frame: .zero)
        super.init(frame: frameRect)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.wantsLayer = true
        addSubview(capsuleView)

        displayField.translatesAutoresizingMaskIntoConstraints = false
        displayField.isEditable = false
        displayField.isSelectable = false
        displayField.isBordered = false
        displayField.isBezeled = false
        displayField.drawsBackground = false
        displayField.focusRingType = .none
        displayField.alignment = .center
        capsuleView.addSubview(displayField)

        NSLayoutConstraint.activate([
            capsuleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsuleView.topAnchor.constraint(equalTo: topAnchor),
            capsuleView.bottomAnchor.constraint(equalTo: bottomAnchor),
            displayField.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor, constant: 12),
            displayField.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor, constant: -12),
            displayField.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
        ])

        updateAppearance()
        updateText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        updateAppearance()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateAppearance()
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        capture(event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return false
        }
        capture(event: event)
        return true
    }

    override func drawFocusRingMask() {
        bounds.fill()
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 52)
    }

    func setStringValue(_ value: String) {
        storedValue = value
        updateText()
        invalidateIntrinsicContentSize()
    }

    func stringValue() -> String {
        storedValue
    }

    func setPlaceholderString(_ value: String) {
        storedPlaceholder = value
        updateText()
        invalidateIntrinsicContentSize()
    }

    private func capture(event: NSEvent) {
        guard let hotkey = HotkeySupport.format(event: event) else {
            return
        }
        storedValue = hotkey
        updateText()
    }

    private func updateText() {
        let hasValue = !storedValue.isEmpty
        displayField.stringValue = hasValue ? displayValue(for: storedValue) : storedPlaceholder
        displayField.textColor = hasValue ? .white : NSColor.white.withAlphaComponent(0.62)
        displayField.font = hasValue
            ? NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            : NSFont.systemFont(ofSize: 11.5, weight: .medium)
    }

    private func displayValue(for value: String) -> String {
        value
            .replacingOccurrences(of: "<cmd>", with: "⌘")
            .replacingOccurrences(of: "<shift>", with: "⇧")
            .replacingOccurrences(of: "<alt>", with: "⌥")
            .replacingOccurrences(of: "<ctrl>", with: "⌃")
            .replacingOccurrences(of: "+", with: " ")
            .uppercased()
    }

    private func updateAppearance() {
        let isFocused = window?.firstResponder === self
        capsuleView.layer?.cornerRadius = 12
        capsuleView.layer?.backgroundColor = NSColor(
            calibratedRed: 0.17,
            green: 0.19,
            blue: 0.22,
            alpha: 1
        ).cgColor
        capsuleView.layer?.borderWidth = isFocused ? 1.5 : 1
        capsuleView.layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.08)).cgColor
        capsuleView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        capsuleView.layer?.shadowOpacity = 1
        capsuleView.layer?.shadowRadius = isFocused ? 10 : 6
        capsuleView.layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
}
