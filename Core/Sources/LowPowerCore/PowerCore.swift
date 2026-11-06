import Foundation

public enum PowerPolicy: String, CaseIterable, Sendable {
    case never = "Never"
    case always = "Always"
    case onlyOnBattery = "Only on Battery"
    case onlyOnPowerAdapter = "Only on Power Adapter"
    
    public var pmsetArguments: (battery: Int, adapter: Int) {
        switch self {
        case .never:
            return (0, 0)
        case .always:
            return (1, 1)
        case .onlyOnBattery:
            return (1, 0)
        case .onlyOnPowerAdapter:
            return (0, 1)
        }
    }
    
    public static func from(pmsetBattery: Int, pmsetAdapter: Int) -> PowerPolicy {
        switch (pmsetBattery, pmsetAdapter) {
        case (0, 0): return .never
        case (1, 1): return .always
        case (1, 0): return .onlyOnBattery
        case (0, 1): return .onlyOnPowerAdapter
        default: return .onlyOnBattery
        }
    }
    
    public static func parseCustomPmset(_ output: String) -> PowerPolicy {
        var batteryLPM: Int?
        var adapterLPM: Int?
        var currentSection = ""
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Battery Power:") {
                currentSection = "Battery"
            } else if trimmed.hasPrefix("AC Power:") {
                currentSection = "AC"
            } else if trimmed.hasPrefix("lowpowermode") {
                let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
                if tokens.count >= 2, let val = Int(tokens[1]) {
                    if currentSection == "Battery" {
                        batteryLPM = val
                    } else if currentSection == "AC" {
                        adapterLPM = val
                    }
                }
            }
        }
        return PowerPolicy.from(pmsetBattery: batteryLPM ?? 0, pmsetAdapter: adapterLPM ?? 0)
    }
}

public enum PowerSourceType: String, Sendable {
    case battery = "Battery"
    case powerAdapter = "Power Adapter"
    case unknown = "Unknown"
}

public struct BatteryLimitStats: Sendable {
    public let capacityPercent: Int
    public let isCharging: Bool
    public let isACConnected: Bool
    public let isLimitEngaged: Bool
    public let rawMinutesRemaining: Int?
    
    public init(
        capacityPercent: Int,
        isCharging: Bool,
        isACConnected: Bool,
        isLimitEngaged: Bool,
        rawMinutesRemaining: Int?
    ) {
        self.capacityPercent = capacityPercent
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.isLimitEngaged = isLimitEngaged
        self.rawMinutesRemaining = rawMinutesRemaining
    }
    
    public var formattedRemaining: String {
        if isLimitEngaged {
            return "Charging on Hold (80% Limit)"
        }
        guard let minutes = rawMinutesRemaining, minutes >= 0 else {
            return isCharging ? "Calculating..." : "Estimating..."
        }
        let hours = minutes / 60
        let mins = minutes % 60
        let timeStr = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        return isCharging ? "\(timeStr) to full" : "\(timeStr) remaining"
    }
}

public struct SudoersHelper: Sendable {
    public static let targetPath = "/private/etc/sudoers.d/lowpowermenu"
    
    public static func generateRule(username: String) -> String {
        "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset\n"
    }
    
    public static func isConfigured(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: targetPath)
    }
}

public struct PowerTelemetryHelper: Sendable {
    public static func calculateWattage(amperage: Double, voltage: Double) -> Double {
        (amperage * voltage) / 1_000_000.0
    }
    
    public static func calculateWattage(systemLoad: Double, isBattery: Bool) -> Double {
        (isBattery ? -1.0 : 1.0) * (systemLoad / 1000.0)
    }
}
