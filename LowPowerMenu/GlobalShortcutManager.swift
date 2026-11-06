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
            print("GlobalShortcutManager: Failed to install event handler. Status: \(installStatus)")
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
            print("GlobalShortcutManager: Failed to register hotkey. Status: \(registerStatus)")
            unregister()
        } else {
            self.hotKeyRef = hotKeyRefOut
            print("GlobalShortcutManager: Hotkey registered successfully.")
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
        print("GlobalShortcutManager: Hotkey unregistered.")
    }
    
    func handleHotKey() {
        print("GlobalShortcutManager: Hotkey Triggered!")
        // Use CFRunLoop in CommonModes to ensure execution even if a menu is open (modal tracking loop)
        let block: @convention(block) () -> Void = { [weak self] in
            self?.onShortcutTriggered?()
        }
        
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
