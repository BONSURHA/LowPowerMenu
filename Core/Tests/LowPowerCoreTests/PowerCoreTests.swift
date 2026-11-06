import XCTest
@testable import LowPowerCore

final class PowerCoreTests: XCTestCase {
    func testPowerPolicyArguments() {
        XCTAssertEqual(PowerPolicy.never.pmsetArguments.battery, 0)
        XCTAssertEqual(PowerPolicy.never.pmsetArguments.adapter, 0)
        
        XCTAssertEqual(PowerPolicy.always.pmsetArguments.battery, 1)
        XCTAssertEqual(PowerPolicy.always.pmsetArguments.adapter, 1)
        
        XCTAssertEqual(PowerPolicy.onlyOnBattery.pmsetArguments.battery, 1)
        XCTAssertEqual(PowerPolicy.onlyOnBattery.pmsetArguments.adapter, 0)
        
        XCTAssertEqual(PowerPolicy.onlyOnPowerAdapter.pmsetArguments.battery, 0)
        XCTAssertEqual(PowerPolicy.onlyOnPowerAdapter.pmsetArguments.adapter, 1)
    }
    
    func testPowerPolicyFromPmset() {
        XCTAssertEqual(PowerPolicy.from(pmsetBattery: 0, pmsetAdapter: 0), .never)
        XCTAssertEqual(PowerPolicy.from(pmsetBattery: 1, pmsetAdapter: 1), .always)
        XCTAssertEqual(PowerPolicy.from(pmsetBattery: 1, pmsetAdapter: 0), .onlyOnBattery)
        XCTAssertEqual(PowerPolicy.from(pmsetBattery: 0, pmsetAdapter: 1), .onlyOnPowerAdapter)
        XCTAssertEqual(PowerPolicy.from(pmsetBattery: 99, pmsetAdapter: 99), .onlyOnBattery)
    }
    
    func testParseCustomPmset() {
        let sampleOutput = """
        Battery Power:
         Sleep On Power Button 1
         lowpowermode         1
         displaysleep         2
        AC Power:
         Sleep On Power Button 1
         lowpowermode         0
         displaysleep         10
        """
        XCTAssertEqual(PowerPolicy.parseCustomPmset(sampleOutput), .onlyOnBattery)
        
        let alwaysOutput = """
        Battery Power:
         lowpowermode         1
        AC Power:
         lowpowermode         1
        """
        XCTAssertEqual(PowerPolicy.parseCustomPmset(alwaysOutput), .always)
        
        let neverOutput = """
        Battery Power:
         lowpowermode         0
        AC Power:
         lowpowermode         0
        """
        XCTAssertEqual(PowerPolicy.parseCustomPmset(neverOutput), .never)
        
        let acOnlyOutput = """
        Battery Power:
         lowpowermode         0
        AC Power:
         lowpowermode         1
        """
        XCTAssertEqual(PowerPolicy.parseCustomPmset(acOnlyOutput), .onlyOnPowerAdapter)
    }
    
    func testBatteryLimitStats() {
        let holdStats = BatteryLimitStats(
            capacityPercent: 80,
            isCharging: false,
            isACConnected: true,
            isLimitEngaged: true,
            rawMinutesRemaining: nil
        )
        XCTAssertEqual(holdStats.formattedRemaining, "Charging on Hold (80% Limit)")
        
        let chargingStats = BatteryLimitStats(
            capacityPercent: 50,
            isCharging: true,
            isACConnected: true,
            isLimitEngaged: false,
            rawMinutesRemaining: 75
        )
        XCTAssertEqual(chargingStats.formattedRemaining, "1h 15m to full")
        
        let dischargingStats = BatteryLimitStats(
            capacityPercent: 90,
            isCharging: false,
            isACConnected: false,
            isLimitEngaged: false,
            rawMinutesRemaining: 150
        )
        XCTAssertEqual(dischargingStats.formattedRemaining, "2h 30m remaining")
    }
    
    func testSudoersHelperRule() {
        let rule = SudoersHelper.generateRule(username: "nicolo")
        XCTAssertEqual(rule, "nicolo ALL=(root) NOPASSWD: /usr/bin/pmset\n")
    }
    
    func testSudoersHelperConfigured() {
        let exists = FileManager.default.fileExists(atPath: SudoersHelper.targetPath)
        XCTAssertEqual(SudoersHelper.isConfigured(), exists)
    }
    
    func testWattageCalculation() {
        // Discharging (negative amperage)
        let dischargeWatts = PowerTelemetryHelper.calculateWattage(amperage: -1500.0, voltage: 12000.0)
        XCTAssertEqual(dischargeWatts, -18.0, accuracy: 0.001)
        
        // Charging (positive amperage)
        let chargeWatts = PowerTelemetryHelper.calculateWattage(amperage: 3500.0, voltage: 12000.0)
        XCTAssertEqual(chargeWatts, 42.0, accuracy: 0.001)
        
        // System load fallback
        let batterySysLoadWatts = PowerTelemetryHelper.calculateWattage(systemLoad: 25000.0, isBattery: true)
        XCTAssertEqual(batterySysLoadWatts, -25.0, accuracy: 0.001)
        
        let acSysLoadWatts = PowerTelemetryHelper.calculateWattage(systemLoad: 30000.0, isBattery: false)
        XCTAssertEqual(acSysLoadWatts, 30.0, accuracy: 0.001)
    }
}
