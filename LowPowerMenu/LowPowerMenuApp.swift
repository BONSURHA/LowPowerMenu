import SwiftUI
import AppKit
import IOKit.ps

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
class AppDelegate: NSObject, NSApplicationDelegate, StatusMenuControllerDelegate {
    private var statusMenuController: StatusMenuController!
    private var settingsWindow: NSWindow?

    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize StatusMenuController
        statusMenuController = StatusMenuController()
        statusMenuController.delegate = self
        
        // Start monitoring power
        setupPowerMonitoring()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: Notification.Name("SettingsChanged"), object: nil)
        
        // Observe power source changes for auto-switching logic
        NotificationCenter.default.addObserver(self, selector: #selector(powerSourceChanged(_:)), name: Notification.Name("PowerSourceChanged"), object: nil)
        
        // Setup Global Shortcut
        setupGlobalShortcut()
        
        // Enforce policy on startup
        // Use retry logic to ensure power source data is available
        enforcePolicyWithRetry()
    }
    
    private func enforcePolicyWithRetry(attempt: Int = 0) {
        let maxAttempts = 10
        let delay = Double(attempt) * 1.0 + 1.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            print("Startup check (attempt \(attempt + 1)/\(maxAttempts))")
            
            if PowerMonitor.shared.isReady || attempt >= maxAttempts - 1 {
                self.enforceAutoSwitchPolicy()
            } else {
                self.enforcePolicyWithRetry(attempt: attempt + 1)
            }
        }
    }
    
    private func hasValidPowerSourceData() -> Bool {
        // Must know LPM state before evaluating policy
        guard PowerMonitor.shared.isLowPowerModeKnown else {
            return false
        }
        
        // Verify we can get a valid snapshot from IOKit
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        
        // Try to get the providing power source type - if this works, we have valid data
        guard let providingSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
            return false
        }
        
        // Valid values are kIOPSACPowerValue or kIOPSBatteryPowerValue
        let validSources = [kIOPSACPowerValue as String, kIOPSBatteryPowerValue as String]
        return validSources.contains(providingSource)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        PowerMonitor.shared.stopMonitoring()
    }
    
    private func setupPowerMonitoring() {
        // Handle status updates
        PowerMonitor.shared.onStatusChange = { [weak self] in
            self?.updateUI()
        }
        
        PowerMonitor.shared.startMonitoring()
    }
    
    private func setupGlobalShortcut() {
        // Set action
        GlobalShortcutManager.shared.onShortcutTriggered = { [weak self] in
            guard let self = self else { return }
            
            // Check constraints: Disable turning ON if on AC power
            let isOnAC = PowerMonitor.shared.checkIfOnACPower()
            let isLowPower = PowerMonitor.shared.isLowPowerMode
            
            if isOnAC && !isLowPower {
                print("Cannot turn on Low Power Mode while on AC power")
                // Optionally play a sound to indicate disabled action
                NSSound.beep()
                return
            }
            
            print("Shortcut triggered! Toggling power mode.")
            self.togglePowerMode()
        }
        
        // Register if enabled in settings
        let enabled = UserDefaults.standard.bool(forKey: "enableGlobalShortcut")
        if enabled {
            // Register default: Cmd+Opt+P (P=0x23/35, Mods=2304)
            GlobalShortcutManager.shared.register(keyCode: 0x23, modifiers: 2304)
        }
    }
    
    private func updateUI() {
        let isLowPower = PowerMonitor.shared.isLowPowerMode
        let isOnAC = PowerMonitor.shared.checkIfOnACPower()
        statusMenuController.updateStatus(isLowPowerMode: isLowPower, isOnACPower: isOnAC)
    }
    
    @objc private func preferencesChanged() {
        updateUI()
    }
    
    // MARK: - Auto-Switching Logic
    
    /// Checks current power state and enforces the logic:
    /// - On AC && Low Power ON -> Action (Turn OFF Low Power Mode)
    /// - On Battery && Low Power OFF -> Action (Turn ON Low Power Mode)
    /// - Otherwise -> No action
    private func enforceAutoSwitchPolicy() {
        guard PowerMonitor.shared.isReady else {
            print("Auto-Switch: Waiting for PowerMonitor to be ready...")
            return
        }
        
        guard PowerMonitor.shared.isLowPowerModeKnown else {
            print("Auto-Switch: Deferring evaluation because Low Power Mode state is completely unknown.")
            return
        }
        
        let isLowPower = PowerMonitor.shared.isLowPowerMode
        let isOnAC = PowerMonitor.shared.checkIfOnACPower()
        
        print("Enforcing Auto-Switch Policy. AC: \(isOnAC), LowPower: \(isLowPower)")

        if isOnAC && isLowPower {
             // Plugged in: turn OFF low power mode
             print("Auto-Switch: Turning OFF Low Power Mode because AC is connected.")
             togglePowerMode()
         } else if !isOnAC && !isLowPower {
             // Unplugged: turn ON low power mode
             print("Auto-Switch: Turning ON Low Power Mode because on Battery.")
             togglePowerMode()
         } else {
             print("Auto-Switch: State is correct. No action needed.")
         }
         
         // Always update UI to match reality
         updateUI()
    }

    @objc private func powerSourceChanged(_ notification: Notification) {
        // Just call the central policy enforcer
        // We know power source just changed, but let's re-read authoritative state inside the function
        enforceAutoSwitchPolicy()
    }
    
    // MARK: - StatusMenuControllerDelegate
    
    func togglePowerMode() {
        ShortcutManager.shared.checkShortcutAndToggle { success in
            if success {
                // Wait a moment then refresh status
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    PowerMonitor.shared.updateLowPowerModeStatus()
                }
            }
        }
    }
    
    func openSettings() {
        if settingsWindow == nil {
            // Create the settings window
            let settingsView = SettingsView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 320),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("Settings")
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false // Keep it around
            settingsWindow = window
        }
        
        // Bring to front
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    

    
    func openShortcutEditor() {
        ShortcutManager.shared.openShortcutEditor()
    }
    
    func refreshStatus() {
        PowerMonitor.shared.updateLowPowerModeStatus()
    }
    
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

