import Carbon
import AppKit

// Global C-compatible handler marked with @convention(c)
private var globalHotKeyHandler: EventHandlerUPP = { (_, _, userData) -> OSStatus in
    if let userData = userData {
        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotKey()
    }
    return noErr
}

class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()
    
    static let keyCodeDefaultsKey = "globalShortcutKeyCode"
    static let modifiersDefaultsKey = "globalShortcutModifiers"
    static let displayDefaultsKey = "globalShortcutDisplay"
    
    static let defaultKeyCode: UInt32 = 0x23 // 'P'
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey) // 2304
    static let defaultDisplay: String = "⌘⌥P"
    
    var currentKeyCode: UInt32 {
        let val = UserDefaults.standard.object(forKey: Self.keyCodeDefaultsKey) as? Int
        return val.map(UInt32.init) ?? Self.defaultKeyCode
    }
    
    var currentModifiers: UInt32 {
        let val = UserDefaults.standard.object(forKey: Self.modifiersDefaultsKey) as? Int
        return val.map(UInt32.init) ?? Self.defaultModifiers
    }
    
    var currentDisplayString: String {
        UserDefaults.standard.string(forKey: Self.displayDefaultsKey) ?? Self.defaultDisplay
    }
    
    func registerSavedShortcut() {
        register(keyCode: currentKeyCode, modifiers: currentModifiers)
    }
    
    func saveAndRegister(keyCode: UInt32, modifiers: UInt32, display: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        UserDefaults.standard.set(Int(modifiers), forKey: Self.modifiersDefaultsKey)
        UserDefaults.standard.set(display, forKey: Self.displayDefaultsKey)
        if UserDefaults.standard.bool(forKey: "enableGlobalShortcut") {
            register(keyCode: keyCode, modifiers: modifiers)
        }
    }
    
    func resetToDefault() {
        saveAndRegister(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers, display: Self.defaultDisplay)
    }
    
    static func recordShortcut(from event: NSEvent) -> (keyCode: UInt32, modifiers: UInt32, display: String)? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }
        guard let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty else { return nil }
        
        var carbonMods: UInt32 = 0
        var display = ""
        if flags.contains(.control) {
            carbonMods |= UInt32(controlKey)
            display += "⌃"
        }
        if flags.contains(.option) {
            carbonMods |= UInt32(optionKey)
            display += "⌥"
        }
        if flags.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
            display += "⇧"
        }
        if flags.contains(.command) {
            carbonMods |= UInt32(cmdKey)
            display += "⌘"
        }
        
        let keyLabel: String
        switch event.keyCode {
        case 49: keyLabel = "Space"
        case 36: keyLabel = "↩"
        case 48: keyLabel = "⇥"
        case 51: keyLabel = "⌫"
        default: keyLabel = chars
        }
        display += keyLabel
        return (UInt32(event.keyCode), carbonMods, display)
    }
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID: EventHotKeyID?
    
    var onShortcutTriggered: (() -> Void)?
    
    var isEnabled: Bool {
        return hotKeyRef != nil
    }
    
    private var isPaused: Bool = false
    private var savedKeyCode: UInt32?
    private var savedModifiers: UInt32?
    
    func setPaused(_ paused: Bool) {
        if paused {
            // If we are pausing, and we are currently registered: unregister but remember we were active
            if hotKeyRef != nil {
                unregister(isPausing: true)
            }
            isPaused = true
        } else {
            // If resuimg, and we were active before: re-register
            isPaused = false
            if let code = savedKeyCode, let mods = savedModifiers {
                register(keyCode: code, modifiers: mods)
            }
        }
    }
    
    func register(keyCode: UInt32 = 0x23, modifiers: UInt32 = UInt32(cmdKey | optionKey)) {
        // Save for restoration
        self.savedKeyCode = keyCode
        self.savedModifiers = modifiers
        
        // Prevent double registration
        if hotKeyRef != nil { unregister() }
        
        if isPaused { return }
        
        // 1. Install Event Handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        
        if installStatus != noErr {
            NSLog("GlobalShortcutManager: Failed to install event handler. Status: %d", installStatus)
            return
        }
        self.eventHandlerRef = handlerRef
        
        // 2. Register HotKey
        // 'LPM1' signature
        let signature = OSType(0x4C504D31)
        hotKeyID = EventHotKeyID(signature: signature, id: 1)
        
        var hotKeyRefOut: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID!,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefOut
        )
        
        if registerStatus != noErr {
            NSLog("GlobalShortcutManager: Failed to register hotkey. Status: %d", registerStatus)
            unregister()
        } else {
            self.hotKeyRef = hotKeyRefOut
        }
    }
    
    func unregister(isPausing: Bool = false) {
        if !isPausing {
            // Full reset
            savedKeyCode = nil
            savedModifiers = nil
            isPaused = false
        }
        
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    func handleHotKey() {
        // Use CFRunLoop in CommonModes to ensure execution even if a menu is open (modal tracking loop)
        let block: @convention(block) () -> Void = { [weak self] in
            self?.onShortcutTriggered?()
        }
        
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
