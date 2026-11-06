import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideOnAC") private var hideOnAC = false
    @AppStorage("enableGlobalShortcut") private var enableGlobalShortcut = false
    
    // Get version info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Info
            VStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "bolt.batteryblock.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(.yellow)
                }
                
                VStack(spacing: 2) {
                    Text("Low Power Menu")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Settings Form
            Form {
                Section {
                    Toggle(isOn: $launchAtLogin) {
                        Label("Launch at Login", systemImage: "desktopcomputer")
                    }
                    .toggleStyle(.switch) // Explicit switch style
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        updateLaunchAtLogin(newValue)
                    }
                    
                    Toggle(isOn: $hideOnAC) {
                        Label("Hide when on Power Adapter/AC", systemImage: "eye.slash")
                    }
                    .toggleStyle(.switch) // Explicit switch style
                    .onChange(of: hideOnAC) { oldValue, newValue in
                        print("Settings: Hide on AC changed to \(newValue)")
                        // Notify AppDelegate to update icon visibility
                        NotificationCenter.default.post(name: Notification.Name("SettingsChanged"), object: nil)
                    }
                    
                    Toggle(isOn: $enableGlobalShortcut) {
                        HStack {
                            Label("Shortcut", systemImage: "keyboard")
                            Spacer()
                            if enableGlobalShortcut {
                                Text("⌘⌥P")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: enableGlobalShortcut) { oldValue, newValue in
                        if newValue {
                            // Default Cmd+Opt+P
                            // P = 0x23 (35), cmd = 256, opt = 2048
                            GlobalShortcutManager.shared.register(keyCode: 0x23, modifiers: 2304) // 256 + 2048
                        } else {
                            GlobalShortcutManager.shared.unregister()
                        }
                    }
                } footer: {
                    if hideOnAC {
                        Text("The menu icon will be hidden when plugged in. It will reappear automatically when unplugged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true) // Prevent scrolling if content fits
        }
        .frame(width: 350, height: 320) // Slightly taller for the header
        .onAppear {
            // Synchronize UI with actual service status just in case
            if #available(macOS 13.0, *) {
                let status = SMAppService.mainApp.status
                print("Settings: Current SMAppService status: \(status.rawValue)")
                launchAtLogin = status == .enabled
            }
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    print("Settings: Attempting to register launch at login")
                    try SMAppService.mainApp.register()
                    print("Settings: Successfully registered launch at login")
                } else {
                    print("Settings: Attempting to unregister launch at login")
                    try SMAppService.mainApp.unregister()
                    print("Settings: Successfully unregistered launch at login")
                }
            } catch {
                print("Failed to update launch at login service: \(error)")
                // Revert the toggle if operation failed
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

