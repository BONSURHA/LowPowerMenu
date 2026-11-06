import AppKit
import SwiftUI
import LowPowerCore

public final class StatusMenuController: NSObject, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
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
        
        let contentView = NativeLiquidStripView(
            onOpenSettings: { [weak self] in
                self?.closePopover()
                (NSApp.delegate as? AppDelegate)?.openPreferencesWindow()
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
        }
    }
    
    @MainActor
    public func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
    
    @MainActor
    public func updateStatus(isLowPowerMode: Bool, isOnACPower: Bool = false) {
        guard let item = statusItem, let button = item.button else { return }
        
        let hideOnAC = UserDefaults.standard.bool(forKey: "hideOnAC")
        item.isVisible = !(hideOnAC && isOnACPower)
        
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
}
