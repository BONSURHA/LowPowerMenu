import SwiftUI
import AppKit
import LowPowerCore

public struct NativeLiquidStripView: View {
    @ObservedObject private var monitor = PowerMonitor.shared
    public var onOpenSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    
    public init(onOpenSettings: (() -> Void)? = nil, onQuit: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: monitor.isLowPowerModeActive ? "dial.low.fill" : "dial.high")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(monitor.isLowPowerModeActive ? Color.orange : Color.secondary)
                Text("Low Power Mode")
                    .font(.system(size: 13, weight: .bold))
                
                // Subtle global toggle shortcut badge
                Text("⌘⌥P")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                Spacer()
                Button(action: {
                    monitor.toggleCurrentState()
                }) {
                    Text(monitor.isLowPowerModeActive ? "Active" : "Normal")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(monitor.isLowPowerModeActive ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                        .foregroundStyle(monitor.isLowPowerModeActive ? Color.orange : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Unified Power & Battery Card
            VStack(alignment: .leading, spacing: 10) {
                // Header Row: Power Source & Percentage
                HStack {
                    HStack(spacing: 5) {
                        if monitor.currentPowerSource == .powerAdapter {
                            Image(systemName: "powerplug.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(monitor.adapterWatts.map { "AC \($0)W" } ?? "AC Power")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        } else {
                            Image(systemName: "battery.100percent")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Battery Power")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(monitor.batteryLimitStats.capacityPercent)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                
                // Progress Bar with 80% Limit Marker
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 7)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: monitor.isLowPowerModeActive ? [Color.orange, Color.yellow] : [Color.secondary.opacity(0.8), Color.secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width * CGFloat(monitor.batteryLimitStats.capacityPercent) / 100.0, geo.size.width)), height: 7)
                        
                        // 80% Limit Notch
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 1.5, height: 11)
                            .offset(x: geo.size.width * 0.8 - 0.75)
                    }
                }
                .frame(height: 11)
                
                // Status / Estimate Row
                HStack {
                    if monitor.batteryLimitStats.isLimitEngaged {
                        Text("Charging Limit: 80%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(monitor.batteryLimitStats.formattedRemaining)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        monitor.openBatteryHealthSettings()
                    }) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Battery Health Settings")
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                // 3-Column Micro-Stats Row
                HStack(spacing: 0) {
                    // Cycle Count (clean number without "cycles")
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(monitor.cycleCount ?? 0)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Dynamic Battery Health Symbol + Percentage
                    HStack(spacing: 4) {
                        Image(systemName: batteryHealthSymbol(for: monitor.batteryHealthPercent ?? 100))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(monitor.batteryHealthPercent ?? 100)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Signed Instantaneous Wattage
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(formattedWattage)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            
            // Apple 4-Policy Selector Card
            VStack(alignment: .leading, spacing: 8) {
                Text("POLICY (AUTO-SWITCHING)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    PolicyPill(title: "Never", key: "1", isSelected: monitor.currentPolicy == .never) {
                        monitor.setPolicy(.never)
                    }
                    PolicyPill(title: "Always", key: "2", isSelected: monitor.currentPolicy == .always) {
                        monitor.setPolicy(.always)
                    }
                    PolicyPill(title: "On Battery", key: "3", isSelected: monitor.currentPolicy == .onlyOnBattery) {
                        monitor.setPolicy(.onlyOnBattery)
                    }
                    PolicyPill(title: "On AC", key: "4", isSelected: monitor.currentPolicy == .onlyOnPowerAdapter) {
                        monitor.setPolicy(.onlyOnPowerAdapter)
                    }
                }
                
                // Relocated Context Explanation Label
                Text(contextExplanationText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            
            // First-Install Helper Warning Banner
            if !monitor.isHelperConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                    Text("Privileged helper required for auto-switching")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Install Helper") {
                        Task {
                            try? await monitor.installSudoersRule()
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Footer
            Divider()
                .padding(.top, 2)
            
            HStack {
                Button(action: {
                    if let onOpenSettings = onOpenSettings {
                        onOpenSettings()
                    } else {
                        AppDelegate.shared?.openPreferencesWindow()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Text("⌘ ,")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                
                Spacer()
                
                Button(action: { onQuit?() }) {
                    HStack(spacing: 5) {
                        Text("Quit")
                        Text("⌘ Q")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .padding(14)
        .frame(width: 300)
    }
    
    private var formattedWattage: String {
        let wattage = monitor.currentWattage ?? 0.0
        if abs(wattage) < 0.05 {
            return "0.0W"
        }
        return String(format: "%+.1fW", wattage)
    }
    
    private func batteryHealthSymbol(for percent: Int) -> String {
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 15..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
    
    private var contextExplanationText: String {
        switch monitor.currentPolicy {
        case .never:
            return "Policy: Disabled under all conditions."
        case .always:
            return "Policy: Permanently active on Battery & AC."
        case .onlyOnBattery:
            return monitor.currentPowerSource == .battery ?
                "Policy: Active while running on battery power." :
                "Policy: Paused while connected to power adapter."
        case .onlyOnPowerAdapter:
            return monitor.currentPowerSource == .powerAdapter ?
                "Policy: Active while connected to power adapter." :
                "Policy: Paused while running on battery power."
        }
    }
}

private struct PolicyPill: View {
    let title: String
    let key: Character
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(key))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}
