import Foundation
import Combine
import IOKit
import IOKit.ps
import AppKit
import LowPowerCore

@MainActor
public final class PowerMonitor: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = PowerMonitor()
    
    // MARK: - Published State
    @Published public private(set) var currentPolicy: PowerPolicy = .onlyOnBattery
    @Published public private(set) var currentPowerSource: PowerSourceType = .battery
    @Published public private(set) var isLowPowerModeActive: Bool = false
    @Published public private(set) var batteryLimitStats: BatteryLimitStats = BatteryLimitStats(
        capacityPercent: 100,
        isCharging: false,
        isACConnected: false,
        isLimitEngaged: false,
        rawMinutesRemaining: nil
    )
    @Published public private(set) var isSudoersConfigured: Bool = false
    public var isHelperConfigured: Bool {
        FileManager.default.fileExists(atPath: "/private/etc/sudoers.d/lowpowermenu")
    }
    @Published public private(set) var isExecuting: Bool = false
    
    // Hardware battery metrics
    @Published public private(set) var cycleCount: Int? = nil
    @Published public private(set) var batteryHealthPercent: Int? = nil
    @Published public private(set) var currentWattage: Double? = nil
    @Published public private(set) var adapterWatts: Int? = nil
    
    // Backward-compatible properties
    public var powerPolicy: PowerPolicy { currentPolicy }
    public var isLowPowerMode: Bool { isLowPowerModeActive }
    public var isLowPowerModeKnown: Bool { true }
    public func checkIfOnACPower() -> Bool { currentPowerSource == .powerAdapter }
    
    public var effectivePolicy: PowerPolicy {
        currentPolicy == .never ? lastActivePolicy : currentPolicy
    }
    
    public var isToggleAvailable: Bool {
        switch effectivePolicy {
        case .always, .never:
            return true
        case .onlyOnBattery:
            return currentPowerSource == .battery
        case .onlyOnPowerAdapter:
            return currentPowerSource == .powerAdapter
        }
    }
    
    private var runLoopSource: CFRunLoopSource?
    private var notifyPort: IONotificationPortRef?
    private var batteryInterestNotification: io_object_t = 0
    private let policyDefaultsKey = "LowPowerMenu_ActivePolicy"
    private let lastActivePolicyDefaultsKey = "LowPowerMenu_LastActivePolicy"
    @Published public private(set) var lastActivePolicy: PowerPolicy = .onlyOnBattery
    
    private override init() {
        super.init()
        loadSavedPolicy()
        setupEventObservers()
        refreshState()
        checkSudoersConfiguration()
    }
    
    deinit {
        if batteryInterestNotification != 0 {
            IOObjectRelease(batteryInterestNotification)
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Event Observation (Zero Polling)
    private func setupEventObservers() {
        // IOKit Power Source change notification
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refreshState()
            }
        }, context).takeRetainedValue()
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        
        // IOKit Kernel Interest Notification (Battery / Charge Limit changes)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let port = IONotificationPortCreate(kIOMainPortDefault) {
                self.notifyPort = port
                IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                IOServiceAddInterestNotification(
                    port,
                    service,
                    kIOGeneralInterest,
                    { refCon, _, _, _ in
                        guard let refCon = refCon else { return }
                        let monitor = Unmanaged<PowerMonitor>.fromOpaque(refCon).takeUnretainedValue()
                        Task { @MainActor in
                            monitor.refreshState()
                        }
                    },
                    selfPtr,
                    &batteryInterestNotification
                )
            }
        }
        
        // ProcessInfo & Workspace notifications
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }
    
    // MARK: - State Refresh
    @MainActor
    public func refreshState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
            return
        }
        
        // Read Darwin Low Power Mode
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        // Read Power Sources Info
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                
                let currentState = description[kIOPSPowerSourceStateKey] as? String
                let isAC = (currentState == kIOPSACPowerValue)
                currentPowerSource = isAC ? .powerAdapter : .battery
                
                let currentCap = description[kIOPSCurrentCapacityKey] as? Int ?? 100
                let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
                let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
                let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int
                
                // Detect Apple 80% Limit / Charging on Hold:
                let obcEngaged = (description["Optimized Battery Charging Engaged"] as? Bool == true) ||
                                 (description["Optimized Battery Charging Engaged"] as? Int == 1)
                let isLimitEngaged = isAC && !isCharging && (obcEngaged || (currentCap >= 79 && currentCap < 100))
                
                batteryLimitStats = BatteryLimitStats(
                    capacityPercent: currentCap,
                    isCharging: isCharging,
                    isACConnected: isAC,
                    isLimitEngaged: isLimitEngaged,
                    rawMinutesRemaining: isCharging ? timeToFull : timeToEmpty
                )
                break
            }
        }
        
        readHardwareBatteryDetails()
        syncPolicyFromSystem()
    }
    
    private func readHardwareBatteryDetails() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }
        
        // Cycle Count
        if let cycles = dict["CycleCount"] as? Int {
            cycleCount = cycles
        }
        
        // Battery Health Percent
        if let batteryData = dict["BatteryData"] as? [String: Any] {
            let designCap = (batteryData["DesignCapacity"] as? Int) ?? (batteryData["DesignCapacity"] as? Double).map(Int.init)
            let fullCap = (batteryData["FullChargeCapacity"] as? Int) ?? (batteryData["AppleRawMaxCapacity"] as? Int)
            if let design = designCap, let full = fullCap, design > 0 {
                batteryHealthPercent = Int(round(Double(full) * 100.0 / Double(design)))
            }
        }
        
        // Current Wattage (Power Consumption & Flow)
        if let amperage = (dict["Amperage"] as? Double) ?? (dict["Amperage"] as? Int).map(Double.init),
           let voltage = (dict["Voltage"] as? Double) ?? (dict["Voltage"] as? Int).map(Double.init) {
            // AppleSmartBattery Amperage is signed: negative when discharging, positive when charging
            currentWattage = (amperage * voltage) / 1_000_000.0
        } else if let telemetry = dict["PowerTelemetryData"] as? [String: Any],
                  let sysLoad = (telemetry["SystemLoad"] as? Double) ?? (telemetry["SystemLoad"] as? Int).map(Double.init),
                  sysLoad > 0 {
            // Fallback to system load: negative on battery discharging, positive on AC
            currentWattage = (currentPowerSource == .battery ? -1.0 : 1.0) * (sysLoad / 1000.0)
        }
        
        // Adapter Watts
        let isConnected = (dict["ExternalConnected"] as? Bool) == true || (dict["ExternalConnected"] as? Int) == 1 || currentPowerSource == .powerAdapter
        if isConnected {
            if let powerDist = dict["PowerDistribution"] as? [String: Any],
               let override = (powerDist["IPDWattageOverride"] as? Int) ?? (powerDist["IPDWattageOverride"] as? Double).map(Int.init),
               override > 0 {
                adapterWatts = override / 1000
            } else if let adapterDetails = dict["AdapterDetails"] as? [String: Any],
                      let watts = adapterDetails["Watts"] as? Int, watts > 0 {
                adapterWatts = watts
            }
        } else {
            adapterWatts = nil
        }
    }
    
    // MARK: - Policy Management
    private func loadSavedPolicy() {
        if let saved = UserDefaults.standard.string(forKey: policyDefaultsKey),
           let policy = PowerPolicy(rawValue: saved) {
            currentPolicy = policy
        } else {
            currentPolicy = .onlyOnBattery
        }
        
        if let savedLast = UserDefaults.standard.string(forKey: lastActivePolicyDefaultsKey),
           let policy = PowerPolicy(rawValue: savedLast),
           policy != .never {
            lastActivePolicy = policy
        } else {
            lastActivePolicy = (currentPolicy != .never) ? currentPolicy : .onlyOnBattery
        }
    }
    
    private func recordLastActivePolicyIfNeeded(_ policy: PowerPolicy) {
        guard policy != .never else { return }
        lastActivePolicy = policy
        UserDefaults.standard.set(policy.rawValue, forKey: lastActivePolicyDefaultsKey)
    }
    
    private func syncPolicyFromSystem() {
        guard !isExecuting else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.qualityOfService = .utility
        process.terminationHandler = { [weak self] _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }
            let actualPolicy = PowerPolicy.parseCustomPmset(output)
            Task { @MainActor [weak self] in
                guard let self = self, !self.isExecuting else { return }
                if self.currentPolicy != actualPolicy {
                    self.recordLastActivePolicyIfNeeded(actualPolicy)
                    self.currentPolicy = actualPolicy
                    UserDefaults.standard.set(actualPolicy.rawValue, forKey: self.policyDefaultsKey)
                }
            }
        }
        try? process.run()
    }
    
    public func setPolicy(_ policy: PowerPolicy) {
        recordLastActivePolicyIfNeeded(policy)
        currentPolicy = policy
        UserDefaults.standard.set(policy.rawValue, forKey: policyDefaultsKey)
        applyPolicy(policy)
    }
    
    public func cyclePolicy() {
        let all = PowerPolicy.allCases
        if let idx = all.firstIndex(of: currentPolicy) {
            let next = all[(idx + 1) % all.count]
            setPolicy(next)
        } else {
            setPolicy(.onlyOnBattery)
        }
    }
    
    public func toggleCurrentState() {
        guard isToggleAvailable else { return }
        if currentPolicy != .never {
            recordLastActivePolicyIfNeeded(currentPolicy)
            setPolicy(.never)
        } else {
            setPolicy(lastActivePolicy)
        }
    }
    
    public func toggleLowPowerMode() {
        toggleCurrentState()
    }
    
    // MARK: - Non-Blocking Execution
    private func applyPolicy(_ policy: PowerPolicy) {
        guard !isExecuting else { return }
        isExecuting = true
        
        let args = policy.pmsetArguments
        let process = Process()
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "/usr/bin/sudo -n /usr/bin/pmset -b lowpowermode \(args.battery) -c lowpowermode \(args.adapter)"
        ]
        process.qualityOfService = .userInitiated
        process.terminationHandler = { [weak self] proc in
            let revertedPolicy: PowerPolicy?
            if proc.terminationStatus != 0 {
                NSLog("LowPowerMenu: Failed to apply power policy (%@): exit code %d. Reverting to system policy.", policy.rawValue, proc.terminationStatus)
                revertedPolicy = PowerMonitor.readActualPolicyFromPmset()
            } else {
                revertedPolicy = nil
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let reverted = revertedPolicy {
                    self.recordLastActivePolicyIfNeeded(reverted)
                    self.currentPolicy = reverted
                    UserDefaults.standard.set(reverted.rawValue, forKey: self.policyDefaultsKey)
                }
                self.isExecuting = false
                self.refreshState()
            }
        }
        do {
            try process.run()
        } catch {
            isExecuting = false
        }
    }
    
    nonisolated public static func readActualPolicyFromPmset() -> PowerPolicy {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            return .onlyOnBattery
        }
        return PowerPolicy.parseCustomPmset(output)
    }
    
    // MARK: - Sudoers Helper
    @discardableResult
    public func checkSudoersConfiguration() -> Bool {
        let exists = FileManager.default.fileExists(atPath: SudoersHelper.targetPath)
        if isSudoersConfigured != exists {
            isSudoersConfigured = exists
        }
        return exists
    }
    
    private nonisolated func runPrivilegedShellCommand(_ command: String) async throws {
        let script = "do shell script \"\(command)\" with administrator privileges"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.qualityOfService = .default
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: NSError(
                        domain: "LowPowerMenu",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: (msg?.isEmpty == false) ? msg! : "Operation cancelled or failed"]
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func installSudoersRule() async throws {
        let username = NSUserName()
        let rule = SudoersHelper.generateRule(username: username)
        let tempPath = "/tmp/lowpowermenu_sudoers"
        try rule.write(toFile: tempPath, atomically: true, encoding: .utf8)
        
        try await runPrivilegedShellCommand("install -m 0440 -o root -g wheel \(tempPath) \(SudoersHelper.targetPath) && visudo -cf \(SudoersHelper.targetPath) && rm -f \(tempPath)")
        _ = self.checkSudoersConfiguration()
    }
    
    public func removeSudoersRule() async throws {
        try await runPrivilegedShellCommand("rm -f \(SudoersHelper.targetPath)")
        _ = self.checkSudoersConfiguration()
    }
    
    public func openBatteryHealthSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension?BatteryHealth") {
            NSWorkspace.shared.open(url)
        }
    }
}
