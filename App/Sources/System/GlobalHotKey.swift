import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses the Carbon hot key API: unlike a global key monitor it sees only the
/// registered combination, so it needs no Accessibility or Input Monitoring
/// permission.
@MainActor
final class GlobalHotKey {
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1
    nonisolated private static let signature: OSType = 0x504F_4C4B  // "POLK"

    private let id: UInt32
    private var reference: EventHotKeyRef?
    private let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        self.reference = reference
        Self.registry[id] = self
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registry[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else { return status }
                let id = hotKeyID.id
                MainActor.assumeIsolated { GlobalHotKey.registry[id]?.action() }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
