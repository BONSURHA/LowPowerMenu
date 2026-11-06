import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideOnAC") private var hideOnAC = false
    @AppStorage("enableGlobalShortcut") private var enableGlobalShortcut = false
    @ObservedObject private var powerMonitor = PowerMonitor.shared
    @State private var installError: String?
    @State private var showingErrorAlert = false
    
    // Get version info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Info
            VStack(spacing: 8) {
                Image(systemName: "dial.high")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.secondary)
                
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
                
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Privileged Helper", systemImage: "lock.shield")
                            Text(powerMonitor.isSudoersConfigured ? "Installed & Active (Passwordless pmset)" : "Required to toggle Low Power Mode")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if powerMonitor.isSudoersConfigured {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Installed & Active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button("Remove", role: .destructive) {
                                    Task {
                                        do {
                                            try await powerMonitor.removeSudoersRule()
                                        } catch {
                                            installError = error.localizedDescription
                                            showingErrorAlert = true
                                        }
                                    }
                                }
                                .controlSize(.small)
                            }
                        } else {
                            Button("Install...") {
                                Task {
                                    do {
                                        try await powerMonitor.installSudoersRule()
                                    } catch {
                                        installError = error.localizedDescription
                                        showingErrorAlert = true
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("System Permissions")
                } footer: {
                    Text("Low Power Mode switching uses macOS pmset, which requires administrator privileges via /private/etc/sudoers.d/lowpowermenu.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true) // Prevent scrolling if content fits
        }
        .frame(width: 380, height: 440)
        .alert("Permissions Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(installError ?? "Unknown error occurred")
        }
        .onAppear {
            powerMonitor.checkSudoersConfiguration()
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

