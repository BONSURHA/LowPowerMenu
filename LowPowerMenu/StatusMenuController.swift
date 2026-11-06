import AppKit
import SwiftUI
import LowPowerCore

@MainActor
public final class StatusMenuController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var keyEventMonitor: Any?
    
    @MainActor
    public func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityTitle("Low Power Menu")
        }
        
        setupPopover()
        updateStatus(isLowPowerMode: PowerMonitor.shared.isLowPowerModeActive)
    }
    
    @MainActor
    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        
        let contentView = NativeLiquidStripView(
            onOpenSettings: { [weak self] in
                self?.closePopover()
                if let appDelegate = AppDelegate.shared {
                    appDelegate.openPreferencesWindow()
                } else {
                    (NSApp.delegate as? AppDelegate)?.openPreferencesWindow()
                }
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        
        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
    }
    
    @MainActor
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        // Right-click or Control-click: instant toggle
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            closePopover()
            PowerMonitor.shared.toggleCurrentState()
            return
        }
        
        // Left-click: toggle popover
        togglePopover(sender)
    }
    
    @MainActor
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            PowerMonitor.shared.refreshState()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            installKeyEventMonitor()
        }
    }
    
    @MainActor
    public func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        removeKeyEventMonitor()
    }
    
    // MARK: - Key Event Monitoring
    @MainActor
    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers
            
            // Cmd+,: Open settings
            if flags.contains(.command) && chars == "," {
                self.closePopover()
                if let appDelegate = AppDelegate.shared {
                    appDelegate.openPreferencesWindow()
                } else {
                    (NSApp.delegate as? AppDelegate)?.openPreferencesWindow()
                }
                return nil
            }
            
            // Cmd+Q: Quit
            if flags.contains(.command) && chars == "q" {
                self.closePopover()
                NSApp.terminate(nil)
                return nil
            }
            
            // Esc: Close popover
            if flags.isEmpty && event.keyCode == 53 {
                self.closePopover()
                return nil
            }
            
            // Number keys 1-4: Switch policy
            if flags.isEmpty, let ch = chars, ch >= "1" && ch <= "4" {
                switch ch {
                case "1": PowerMonitor.shared.setPolicy(.never)
                case "2": PowerMonitor.shared.setPolicy(.always)
                case "3": PowerMonitor.shared.setPolicy(.onlyOnBattery)
                case "4": PowerMonitor.shared.setPolicy(.onlyOnPowerAdapter)
                default: break
                }
                return nil
            }
            
            return event
        }
    }
    
    @MainActor
    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    // MARK: - NSPopoverDelegate
    @MainActor
    public func popoverDidClose(_ notification: Notification) {
        removeKeyEventMonitor()
    }
    
    @MainActor
    public func updateStatus(isLowPowerMode: Bool, isOnACPower: Bool = false) {
        let updateBlock = { [weak self] in
            guard let self = self, let item = self.statusItem, let button = item.button else { return }
            
            let hideOnAC = UserDefaults.standard.bool(forKey: "hideOnAC")
            let targetVisibility = !(hideOnAC && isOnACPower)
            if item.isVisible != targetVisibility {
                item.isVisible = targetVisibility
            }
            
            let symbolName = isLowPowerMode ? "dial.low.fill" : "dial.high"
            let description = isLowPowerMode ? "Low Power Mode On" : "Low Power Mode Off"
            
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = isLowPowerMode ? "LPM" : "OFF"
            }
            
            button.setAccessibilityValue(description)
        }
        
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }
}
