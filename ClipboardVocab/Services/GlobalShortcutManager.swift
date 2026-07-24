import AppKit
import Carbon
import os

/// Lightweight global keyboard shortcut manager using Carbon's `RegisterEventHotKey`.
///
/// Registers a single global hotkey (default: Command+Shift+C) and calls a closure
/// when that key combination is pressed from any application context.
///
/// This replaces the `KeyboardShortcuts` SPM dependency to avoid `#Preview` macro
/// build failures in CLI/CI environments.
final class GlobalShortcutManager {

    // MARK: - Private state

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Shared instance to keep the event handler alive for the app lifetime.
    static let shared = GlobalShortcutManager()

    // MARK: - Register

    /// Register Command+Shift+C (or a custom key/modifiers) as a global hotkey.
    /// The `action` closure is called on the main thread when the shortcut fires.
    func register(
        keyCode: Int = Int(kVK_ANSI_C),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        action: @escaping () -> Void
    ) {
        self.action = action
        AppLogger.shortcut.info("Enregistrement du raccourci global (Cmd+Shift+C)")

        let id = EventHotKeyID(signature: fourCharCode("CLPV"), id: 1)

        // Install a Carbon event handler on the application event target
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                AppLogger.shortcut.debug("Raccourci global déclenché")
                DispatchQueue.main.async { manager.action?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    /// Unregister the global hotkey.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            AppLogger.shortcut.info("Raccourci global désenregistré")
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    deinit { unregister() }
}

// MARK: - Helpers

private func fourCharCode(_ string: String) -> FourCharCode {
    assert(string.count == 4)
    var code: FourCharCode = 0
    for char in string.unicodeScalars {
        code = (code << 8) + FourCharCode(char.value)
    }
    return code
}
