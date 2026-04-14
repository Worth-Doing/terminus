import Foundation
import Darwin
import IOKit

// MARK: - System Metrics Snapshot

public struct SystemMetrics: Sendable {
    public var cpu: CPUMetrics
    public var memory: MemoryMetrics
    public var gpu: GPUMetrics
    public var disk: DiskMetrics
    public var network: NetworkMetrics
    public var topProcesses: [ProcessInfo]
    public var timestamp: Date

    public init() {
        self.cpu = CPUMetrics()
        self.memory = MemoryMetrics()
        self.gpu = GPUMetrics()
        self.disk = DiskMetrics()
        self.network = NetworkMetrics()
        self.topProcesses = []
        self.timestamp = Date()
    }
}

// MARK: - CPU Metrics

public struct CPUMetrics: Sendable {
    public var userPercent: Double = 0
    public var systemPercent: Double = 0
    public var idlePercent: Double = 100
    public var totalUsagePercent: Double = 0
    public var coreCount: Int = 0
    public var perCoreUsage: [Double] = []
    public var temperature: Double? = nil
    public var processCount: Int = 0
    public var threadCount: Int = 0
}

// MARK: - Memory Metrics

public struct MemoryMetrics: Sendable {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var activeBytes: UInt64 = 0
    public var wiredBytes: UInt64 = 0
    public var compressedBytes: UInt64 = 0
    public var swapUsedBytes: UInt64 = 0
    public var pressure: Double = 0  // 0.0 to 1.0

    public var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

// MARK: - GPU Metrics

public struct GPUMetrics: Sendable {
    public var name: String = "Unknown"
    public var utilizationPercent: Double = 0
    public var temperature: Double? = nil
    public var vramTotal: UInt64 = 0
    public var vramUsed: UInt64 = 0
}

// MARK: - Disk Metrics

public struct DiskMetrics: Sendable {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var readBytesPerSec: UInt64 = 0
    public var writeBytesPerSec: UInt64 = 0

    public var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

// MARK: - Network Metrics

public struct NetworkMetrics: Sendable {
    public var receivedBytesPerSec: UInt64 = 0
    public var sentBytesPerSec: UInt64 = 0
    public var totalReceivedBytes: UInt64 = 0
    public var totalSentBytes: UInt64 = 0
}

// MARK: - Process Info

public struct ProcessInfo: Sendable, Identifiable {
    public let id: Int32  // pid
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(id: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
