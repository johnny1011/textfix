import AppKit

let application = NSApplication.shared
let delegate = TextFixAppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
