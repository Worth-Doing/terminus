import SwiftUI

// MARK: - Metrics Panel View

public struct MetricsPanel: View {
    @State private var monitor = SystemMonitor()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                    Text("System Monitor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.bottom, 4)

                // CPU Section
                MetricSection(title: "CPU", icon: "cpu") {
                    GaugeBar(
                        value: monitor.metrics.cpu.totalUsagePercent,
                        maxValue: 100,
                        color: cpuColor(monitor.metrics.cpu.totalUsagePercent),
                        label: String(format: "%.1f%%", monitor.metrics.cpu.totalUsagePercent)
                    )

                    MiniSparkline(
                        data: monitor.cpuHistory,
                        maxValue: 100,
                        color: .blue
                    )
                    .frame(height: 32)

                    HStack {
                        MetricLabel("User", String(format: "%.1f%%", monitor.metrics.cpu.userPercent))
                        Spacer()
                        MetricLabel("System", String(format: "%.1f%%", monitor.metrics.cpu.systemPercent))
                        Spacer()
                        MetricLabel("Cores", "\(monitor.metrics.cpu.coreCount)")
                    }

                    if monitor.metrics.cpu.processCount > 0 {
                        HStack {
                            MetricLabel("Processes", "\(monitor.metrics.cpu.processCount)")
                            Spacer()
                        }
                    }
                }

                // Memory Section
                MetricSection(title: "Memory", icon: "memorychip") {
                    GaugeBar(
                        value: monitor.metrics.memory.usagePercent,
                        maxValue: 100,
                        color: memoryColor(monitor.metrics.memory.pressure),
                        label: String(format: "%.1f%%", monitor.metrics.memory.usagePercent)
                    )

                    MiniSparkline(
                        data: monitor.memoryHistory,
                        maxValue: 100,
                        color: .green
                    )
                    .frame(height: 32)

                    HStack {
                        MetricLabel("Used", formatBytes(monitor.metrics.memory.usedBytes))
                        Spacer()
                        MetricLabel("Total", formatBytes(monitor.metrics.memory.totalBytes))
                    }

                    HStack {
                        MetricLabel("Active", formatBytes(monitor.metrics.memory.activeBytes))
                        Spacer()
                        MetricLabel("Wired", formatBytes(monitor.metrics.memory.wiredBytes))
                    }

                    if monitor.metrics.memory.compressedBytes > 0 {
                        HStack {
                            MetricLabel("Compressed", formatBytes(monitor.metrics.memory.compressedBytes))
                            Spacer()
                            if monitor.metrics.memory.swapUsedBytes > 0 {
                                MetricLabel("Swap", formatBytes(monitor.metrics.memory.swapUsedBytes))
                            }
                        }
                    }
                }

                // GPU Section
                MetricSection(title: "GPU", icon: "display") {
                    Text(monitor.metrics.gpu.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    GaugeBar(
                        value: monitor.metrics.gpu.utilizationPercent,
                        maxValue: 100,
                        color: .purple,
                        label: String(format: "%.0f%%", monitor.metrics.gpu.utilizationPercent)
                    )

                    if monitor.metrics.gpu.vramTotal > 0 {
                        HStack {
                            MetricLabel("VRAM", formatBytes(monitor.metrics.gpu.vramUsed))
                            Spacer()
                            MetricLabel("Total", formatBytes(monitor.metrics.gpu.vramTotal))
                        }
                    }
                }

                // Disk Section
                MetricSection(title: "Disk", icon: "internaldrive") {
                    GaugeBar(
                        value: monitor.metrics.disk.usagePercent,
                        maxValue: 100,
                        color: .orange,
                        label: String(format: "%.1f%%", monitor.metrics.disk.usagePercent)
                    )

                    HStack {
                        MetricLabel("Used", formatBytes(monitor.metrics.disk.usedBytes))
                        Spacer()
                        MetricLabel("Free", formatBytes(monitor.metrics.disk.freeBytes))
                    }
                }

                // Network Section
                MetricSection(title: "Network", icon: "network") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green)
                                Text(formatBytesPerSec(monitor.metrics.network.receivedBytesPerSec))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Text("Download")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(formatBytesPerSec(monitor.metrics.network.sentBytesPerSec))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.white)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                            }
                            Text("Upload")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Top Processes
                if !monitor.metrics.topProcesses.isEmpty {
                    MetricSection(title: "Top Processes", icon: "list.number") {
                        ForEach(monitor.metrics.topProcesses) { proc in
                            HStack {
                                Text(proc.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: 100, alignment: .leading)

                                Spacer()

                                Text(formatBytes(proc.memoryBytes))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .onAppear { monitor.start(interval: 1.5) }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Color Helpers

    private func cpuColor(_ percent: Double) -> Color {
        if percent > 80 { return .red }
        if percent > 50 { return .orange }
        return .blue
    }

    private func memoryColor(_ pressure: Double) -> Color {
        if pressure > 0.85 { return .red }
        if pressure > 0.65 { return .yellow }
        return .green
    }
}

// MARK: - Metric Section

struct MetricSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Gauge Bar

struct GaugeBar: View {
    let value: Double
    let maxValue: Double
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.8), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(value / maxValue)))
                }
            }
            .frame(height: 8)

            HStack {
                Spacer()
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Mini Sparkline

struct MiniSparkline: View {
    let data: [Double]
    let maxValue: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)
                    let height = geo.size.height

                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value / maxValue) * height)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color.opacity(0.7), lineWidth: 1.5)

                // Fill area under curve
                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)
                    let height = geo.size.height

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value / maxValue) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: geo.size.width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Metric Label

struct MetricLabel: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Formatting

func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 { return String(format: "%.1f GB", gb) }
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    if kb >= 1 { return String(format: "%.0f KB", kb) }
    return "\(bytes) B"
}

func formatBytesPerSec(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024

    if mb >= 1 { return String(format: "%.1f MB/s", mb) }
    if kb >= 1 { return String(format: "%.0f KB/s", kb) }
    return "\(bytes) B/s"
}
