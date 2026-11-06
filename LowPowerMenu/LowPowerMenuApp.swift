import SwiftUI
import AppKit
import Combine
import LowPowerCore

@main
struct LowPowerMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) var shared: AppDelegate?
    
    private var statusMenuController: StatusMenuController!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
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
        
        Publishers.CombineLatest(PowerMonitor.shared.$isLowPowerModeActive, PowerMonitor.shared.$currentPowerSource)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLowPower, source in
                let isOnAC = (source == .powerAdapter)
                self?.statusMenuController.updateStatus(isLowPowerMode: isLowPower, isOnACPower: isOnAC)
            }
            .store(in: &cancellables)
        
        // Initial UI sync
        updateUI()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func powerStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    @objc private func preferencesChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    @MainActor
    private func updateUI() {
        let isLowPower = PowerMonitor.shared.isLowPowerModeActive
        let isOnAC = (PowerMonitor.shared.currentPowerSource == .powerAdapter) || PowerMonitor.shared.checkIfOnACPower()
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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
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
