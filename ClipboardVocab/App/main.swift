import AppKit

// Entry point: launch the NSApplication with our custom AppDelegate
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
