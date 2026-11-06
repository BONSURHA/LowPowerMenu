import SwiftUI
import AppKit

struct BatteryInfoView: View {
    @State private var stats: BatteryStats?
    @State private var timer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if let stats = stats {
                VStack(spacing: 8) {
                    
                    // Capacity Bar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Battery Charge")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(Int(stats.currentCapacity))%")
                                .font(.system(size: 13))
                                .monospacedDigit()
                        }
                        
                        Gauge(value: stats.currentCapacity, in: 0...100) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .gaugeStyle(.linearCapacity(color: stats.currentCapacity <= 20 ? Color(nsColor: .systemRed) : .accentColor))
                    }
                    
                    // Health Bar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Battery Health")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(String(format: "%.1f%%", stats.healthPercent))
                                .font(.system(size: 13))
                                .monospacedDigit()
                        }
                        
                        Gauge(value: stats.healthPercent, in: 0...100) {
                            EmptyView()
                        }
                        .gaugeStyle(.linearCapacity(color: stats.healthPercent <= 80 ? Color(nsColor: .systemOrange) : .accentColor))
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Text Stats Grid
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("Time until \(stats.isCharging ? "full" : "empty")")
                                .font(.system(size: 13, weight: .medium))
                            Text(stats.formattedTimeRemaining)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                             Text("Cycles")
                                .font(.system(size: 13, weight: .medium))
                             Text("\(stats.cycleCount)")
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                             Text("Temperature")
                                .font(.system(size: 13, weight: .medium))
                             Text(String(format: "%.1f °C", stats.temperature))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                        }
                        
                        GridRow {
                             // Status: Charging / Not Charging
                             // If amperage >= 10mA it is charging.
                             let isCharging = stats.amperage > 10
                             let powerVal = (stats.voltage * stats.amperage) / 1000.0
                             
                             Text(isCharging ? "Charging" : "Not Charging")
                                .font(.system(size: 13, weight: .medium))
                             
                             Text(String(format: "%.1f W", abs(powerVal)))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                                .foregroundStyle(isCharging ? Color(nsColor: .systemGreen) : Color(nsColor: .secondaryLabelColor))
                        }
                    }
                }
            } else {
                ProgressView("Loading...")
                    .scaleEffect(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .onAppear {
            refreshStats()
            // Auto refresh every 5 seconds while open.
            // Critical: Must use .common mode to run inside an open NSMenu (NSEventTrackingRunLoopMode).
            let t = Timer(timeInterval: 5.0, repeats: true) { _ in
                refreshStats()
            }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func refreshStats() {
        self.stats = BatteryInfoManager.shared.getBatteryStats()
    }
}

struct LinearCapacityGaugeStyle: GaugeStyle {
    var color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
                
                // Filled track
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * (configuration.value), height: 8)
            }
        }
        .frame(height: 8)
    }
}

extension GaugeStyle where Self == LinearCapacityGaugeStyle {
    static func linearCapacity(color: Color) -> LinearCapacityGaugeStyle {
        LinearCapacityGaugeStyle(color: color)
    }
}
