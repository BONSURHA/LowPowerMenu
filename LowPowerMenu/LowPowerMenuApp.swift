import SwiftUI
import AppKit
import LowPowerCore

@main
struct LowPowerMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController!
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize StatusMenuController
        statusMenuController = StatusMenuController()
        statusMenuController.setupStatusItem()
        
        // Setup Global Shortcut
        setupGlobalShortcut()
        
        // Listen for power state changes to keep menu bar icon updated
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: Notification.Name("SettingsChanged"),
            object: nil
        )
        
        // Initial UI sync
        updateUI()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func powerStateDidChange() {
        updateUI()
    }
    
    @objc private func preferencesChanged() {
        updateUI()
    }
    
    private func updateUI() {
        let isLowPower = PowerMonitor.shared.isLowPowerModeActive
        let isOnAC = PowerMonitor.shared.checkIfOnACPower()
        statusMenuController.updateStatus(isLowPowerMode: isLowPower, isOnACPower: isOnAC)
    }
    
    private func setupGlobalShortcut() {
        GlobalShortcutManager.shared.onShortcutTriggered = {
            PowerMonitor.shared.toggleCurrentState()
        }
        
        // Register if enabled in settings
        let enabled = UserDefaults.standard.bool(forKey: "enableGlobalShortcut")
        if enabled {
            // Default: Cmd+Opt+P (P=0x23, Mods=2304)
            GlobalShortcutManager.shared.register(keyCode: 0x23, modifiers: 2304)
        }
    }
    
    func openPreferencesWindow() {
        openSettings()
    }
    
    func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 320),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.setFrameAutosaveName("Settings")
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
