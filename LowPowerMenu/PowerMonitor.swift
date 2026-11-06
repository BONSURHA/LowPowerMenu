import Foundation
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
    @Published public private(set) var isExecuting: Bool = false
    
    // Backward-compatible properties
    public var isLowPowerMode: Bool { isLowPowerModeActive }
    public var isLowPowerModeKnown: Bool { true }
    public func checkIfOnACPower() -> Bool { currentPowerSource == .powerAdapter }
    
    private var runLoopSource: CFRunLoopSource?
    private let policyDefaultsKey = "LowPowerMenu_ActivePolicy"
    
    private override init() {
        super.init()
        loadSavedPolicy()
        setupEventObservers()
        refreshState()
        checkSudoersConfiguration()
    }
    
    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
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
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        
        // NSProcessInfo & Workspace notifications
        NotificationCenter.default.addObserver(
            forName: NSProcessInfo.powerStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshState()
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshState()
        }
    }
    
    // MARK: - State Refresh
    public func refreshState() {
        // Read Darwin Low Power Mode
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        // Read Power Sources Info
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
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
            // When connected to AC, capacity >= 79%, not charging, or timeToFull is -1 while connected
            let isLimitEngaged = isAC && currentCap >= 79 && currentCap < 100 && !isCharging
            
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
    
    // MARK: - Policy Management
    private func loadSavedPolicy() {
        if let saved = UserDefaults.standard.string(forKey: policyDefaultsKey),
           let policy = PowerPolicy(rawValue: saved) {
            currentPolicy = policy
        } else {
            currentPolicy = .onlyOnBattery
        }
    }
    
    public func setPolicy(_ policy: PowerPolicy) {
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
        if isLowPowerModeActive {
            setPolicy(.never)
        } else {
            setPolicy(.onlyOnBattery)
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
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c",
                "sudo -n /usr/bin/pmset -b lowpowermode \(args.battery) -c lowpowermode \(args.adapter) 2>/dev/null || /usr/bin/pmset -b lowpowermode \(args.battery) -c lowpowermode \(args.adapter) 2>/dev/null"
            ]
            
            try? process.run()
            process.waitUntilExit()
            
            await MainActor.run {
                self.isExecuting = false
                self.refreshState()
            }
        }
    }
    
    // MARK: - Sudoers Helper
    public func checkSudoersConfiguration() {
        let exists = FileManager.default.fileExists(atPath: SudoersHelper.targetPath)
        isSudoersConfigured = exists
    }
    
    public func installSudoersRule() throws {
        let username = NSUserName()
        let rule = SudoersHelper.generateRule(username: username)
        let tempPath = "/tmp/lowpowermenu_sudoers"
        try rule.write(toFile: tempPath, atomically: true, encoding: .utf8)
        
        let script = "do shell script \"install -m 0440 -o root -g wheel \(tempPath) \(SudoersHelper.targetPath) && visudo -cf \(SudoersHelper.targetPath) && rm -f \(tempPath)\" with administrator privileges"
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                throw NSError(domain: "LowPowerMenu", code: 1, userInfo: [NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] ?? "Sudoers install failed"])
            }
        }
        checkSudoersConfiguration()
    }
    
    public func openBatteryHealthSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension?BatteryHealth") {
            NSWorkspace.shared.open(url)
        }
    }
}
