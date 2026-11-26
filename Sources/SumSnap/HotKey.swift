import AppKit
import Carbon.HIToolbox

/// Globalny skrót klawiszowy przez Carbon `RegisterEventHotKey`.
/// Wybrany świadomie: w odróżnieniu od `NSEvent.addGlobalMonitor` nie wymaga
/// uprawnienia "Dostępność".
final class HotKeyManager {
    static let shared = HotKeyManager()

    struct Combo: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
    }

    static let presets: [Combo] = [
        Combo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘S"),
        Combo(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘4"),
        Combo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘D"),
        Combo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey | optionKey | cmdKey), label: "⇧⌥⌘S"),
    ]

    var onFire: (() -> Void)?
    private(set) var current: Combo?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerInstalled = false

    private init() {}

    @discardableResult
    func register(_ combo: Combo) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x53554D53), id: 1) // 'SUMS'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)

        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        current = combo
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, &handlerRef)
        handlerInstalled = true
    }
}

private let hotKeyCallback: EventHandlerUPP = { _, _, _ in
    DispatchQueue.main.async {
        HotKeyManager.shared.onFire?()
    }
    return noErr
}
