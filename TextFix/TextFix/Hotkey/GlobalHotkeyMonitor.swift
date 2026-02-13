import Cocoa
import CoreGraphics
import os.log

final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            logger.error("Failed to create event tap - Input Monitoring permission needed")
            DispatchQueue.main.async { [weak self] in
                self?.appState?.showNotification(
                    title: "Hotkey disabled",
                    message: "Enable Input Monitoring for TextFix, then relaunch."
                )
            }
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap created and enabled successfully")
    }

    private func handleEvent(_ event: CGEvent) {
        guard event.type == .keyDown, let state = appState else { return }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Debug: log all Cmd-modified keypresses
        if flags.contains(.maskCommand) {
            logger.info("KeyDown: keycode=\(keycode) flags=\(flags.rawValue)")
        }

        if let spec = state.fixHotkeySpec, spec.matches(keycode: keycode, flags: flags) {
            logger.info("Fix hotkey detected keycode=\(keycode)")
            DispatchQueue.main.async { state.onFixHotkey() }
        } else if let spec = state.contextHotkeySpec, spec.matches(keycode: keycode, flags: flags) {
            logger.info("Context hotkey detected keycode=\(keycode)")
            DispatchQueue.main.async { state.onContextHotkey() }
        } else if let spec = state.promptHotkeySpec, spec.matches(keycode: keycode, flags: flags) {
            logger.info("Prompt hotkey detected keycode=\(keycode)")
            DispatchQueue.main.async { state.onPromptHotkey() }
        }
    }
}
