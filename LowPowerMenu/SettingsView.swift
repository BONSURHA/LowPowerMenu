import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideOnAC") private var hideOnAC = false
    @AppStorage("enableGlobalShortcut") private var enableGlobalShortcut = false
    @AppStorage("globalShortcutDisplay") private var globalShortcutDisplay = GlobalShortcutManager.defaultDisplay
    @ObservedObject private var powerMonitor = PowerMonitor.shared
    
    @State private var isRecordingShortcut = false
    @State private var keyMonitor: Any?
    @State private var installError: String?
    @State private var showingErrorAlert = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
    }
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            helperTab
                .tabItem {
                    Label("Helper", systemImage: "lock.shield")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 240)
        .alert("Permissions Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(installError ?? "Unknown error occurred")
        }
        .onAppear {
            powerMonitor.checkSudoersConfiguration()
            if #available(macOS 13.0, *) {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
        .onDisappear {
            stopRecordingShortcut()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Label("Launch at Login", systemImage: "desktopcomputer")
                }
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }
                
                Toggle(isOn: $hideOnAC) {
                    Label("Hide on AC Power", systemImage: "eye.slash")
                }
                .toggleStyle(.switch)
                .onChange(of: hideOnAC) { _, _ in
                    NotificationCenter.default.post(name: Notification.Name("SettingsChanged"), object: nil)
                }
            }
            
            Section {
                HStack {
                    Toggle(isOn: $enableGlobalShortcut) {
                        Label("Global Shortcut", systemImage: "keyboard")
                    }
                    .toggleStyle(.switch)
                    .onChange(of: enableGlobalShortcut) { _, newValue in
                        if newValue {
                            GlobalShortcutManager.shared.registerSavedShortcut()
                        } else {
                            stopRecordingShortcut()
                            GlobalShortcutManager.shared.unregister()
                        }
                    }
                    
                    if enableGlobalShortcut {
                        Spacer()
                        Button(action: {
                            if isRecordingShortcut {
                                stopRecordingShortcut()
                            } else {
                                startRecordingShortcut()
                            }
                        }) {
                            Text(isRecordingShortcut ? "Press keys…" : globalShortcutDisplay)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.bordered)
                        .tint(isRecordingShortcut ? .orange : .primary)
                        .controlSize(.small)
                        .help("Click to record a new shortcut (Esc to cancel)")
                        
                        if globalShortcutDisplay != GlobalShortcutManager.defaultDisplay {
                            Button(action: {
                                stopRecordingShortcut()
                                GlobalShortcutManager.shared.resetToDefault()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Reset shortcut to default")
                            .help("Reset to default (\(GlobalShortcutManager.defaultDisplay))")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
    
    // MARK: - Helper Tab
    private var helperTab: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: powerMonitor.isSudoersConfigured ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(powerMonitor.isSudoersConfigured ? Color.green : Color.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privileged Helper")
                            .font(.system(size: 13, weight: .semibold))
                        Text(powerMonitor.isSudoersConfigured ? "Installed & Active (Passwordless pmset)" : "Required to switch Low Power Mode policies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if powerMonitor.isSudoersConfigured {
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
                    } else {
                        Button("Install…") {
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
            } footer: {
                Text("Installs a scoped sudoers rule at /private/etc/sudoers.d/lowpowermenu allowing passwordless /usr/bin/pmset execution.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "dial.high")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            
            VStack(spacing: 3) {
                Text("Low Power Menu")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("Lightweight native macOS Low Power Mode & Battery telemetry controller.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Shortcut Recording
    private func startRecordingShortcut() {
        isRecordingShortcut = true
        GlobalShortcutManager.shared.setPaused(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc (53) cancels recording
            if event.keyCode == 53 {
                stopRecordingShortcut()
                return nil
            }
            if let recorded = GlobalShortcutManager.recordShortcut(from: event) {
                GlobalShortcutManager.shared.saveAndRegister(
                    keyCode: recorded.keyCode,
                    modifiers: recorded.modifiers,
                    display: recorded.display
                )
                stopRecordingShortcut()
                return nil
            }
            return event
        }
    }
    
    private func stopRecordingShortcut() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if isRecordingShortcut {
            isRecordingShortcut = false
            GlobalShortcutManager.shared.setPaused(false)
        }
    }
    
    // MARK: - Launch at Login
    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }
}
