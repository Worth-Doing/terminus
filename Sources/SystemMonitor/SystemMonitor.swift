import Foundation
import Darwin

// MARK: - System Monitor

@Observable
public final class SystemMonitor: @unchecked Sendable {
    public private(set) var metrics = SystemMetrics()
    public private(set) var cpuHistory: [Double] = []
    public private(set) var memoryHistory: [Double] = []
    public private(set) var networkInHistory: [UInt64] = []
    public private(set) var networkOutHistory: [UInt64] = []

    private let historyLength = 60  // 60 data points
    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info?
    private var previousNetworkBytes: (rx: UInt64, tx: UInt64) = (0, 0)
    private var previousTimestamp: Date?

    public init() {}

    // MARK: - Start / Stop

    public func start(interval: TimeInterval = 1.5) {
        stop()
        // Initial sample
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Sample All

    private func sample() {
        var m = SystemMetrics()
        m.timestamp = Date()

        sampleCPU(&m.cpu)
        sampleMemory(&m.memory)
        sampleDisk(&m.disk)
        sampleNetwork(&m.network)
        sampleGPU(&m.gpu)
        m.topProcesses = sampleTopProcesses(limit: 8)

        metrics = m

        // Update history
        cpuHistory.append(m.cpu.totalUsagePercent)
        memoryHistory.append(m.memory.usagePercent)
        networkInHistory.append(m.network.receivedBytesPerSec)
        networkOutHistory.append(m.network.sentBytesPerSec)

        if cpuHistory.count > historyLength { cpuHistory.removeFirst() }
        if memoryHistory.count > historyLength { memoryHistory.removeFirst() }
        if networkInHistory.count > historyLength { networkInHistory.removeFirst() }
        if networkOutHistory.count > historyLength { networkOutHistory.removeFirst() }
    }

    // MARK: - CPU

    private func sampleCPU(_ cpu: inout CPUMetrics) {
        cpu.coreCount = Foundation.ProcessInfo.processInfo.processorCount

        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        if let prev = previousCPUInfo {
            let userDiff = Double(loadInfo.cpu_ticks.0 - prev.cpu_ticks.0)
            let systemDiff = Double(loadInfo.cpu_ticks.1 - prev.cpu_ticks.1)
            let idleDiff = Double(loadInfo.cpu_ticks.2 - prev.cpu_ticks.2)
            let niceDiff = Double(loadInfo.cpu_ticks.3 - prev.cpu_ticks.3)
            let total = userDiff + systemDiff + idleDiff + niceDiff

            if total > 0 {
                cpu.userPercent = (userDiff + niceDiff) / total * 100
                cpu.systemPercent = systemDiff / total * 100
                cpu.idlePercent = idleDiff / total * 100
                cpu.totalUsagePercent = 100 - cpu.idlePercent
            }
        }
        previousCPUInfo = loadInfo

        // Process and thread counts
        var procCount: Int32 = 0
        var threadCount: Int32 = 0
        getProcessAndThreadCounts(&procCount, &threadCount)
        cpu.processCount = Int(procCount)
        cpu.threadCount = Int(threadCount)
    }

    private func getProcessAndThreadCounts(_ procs: inout Int32, _ threads: inout Int32) {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        procs = Int32(count)
        threads = 0  // Thread count requires iterating processes
    }

    // MARK: - Memory

    private func sampleMemory(_ mem: inout MemoryMetrics) {
        mem.totalBytes = Foundation.ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        mem.activeBytes = UInt64(vmStats.active_count) * pageSize
        mem.wiredBytes = UInt64(vmStats.wire_count) * pageSize
        mem.compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        mem.freeBytes = UInt64(vmStats.free_count) * pageSize

        mem.usedBytes = mem.activeBytes + mem.wiredBytes + mem.compressedBytes

        // Memory pressure estimate
        let usedRatio = Double(mem.usedBytes) / Double(mem.totalBytes)
        mem.pressure = min(1.0, usedRatio)

        // Swap
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        mem.swapUsedBytes = swapUsage.xsu_used
    }

    // MARK: - Disk

    private func sampleDisk(_ disk: inout DiskMetrics) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            if let total = attrs[.systemSize] as? UInt64,
               let free = attrs[.systemFreeSize] as? UInt64 {
                disk.totalBytes = total
                disk.freeBytes = free
                disk.usedBytes = total - free
            }
        } catch {
            // Ignore
        }
    }

    // MARK: - Network

    private func sampleNetwork(_ net: inout NetworkMetrics) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0

        var ptr = firstAddr
        while true {
            let iface = ptr.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let data = unsafeBitCast(iface.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                totalRx += UInt64(data.pointee.ifi_ibytes)
                totalTx += UInt64(data.pointee.ifi_obytes)
            }
            guard let next = iface.ifa_next else { break }
            ptr = next
        }

        net.totalReceivedBytes = totalRx
        net.totalSentBytes = totalTx

        let now = Date()
        if let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let rxDiff = totalRx > previousNetworkBytes.rx ? totalRx - previousNetworkBytes.rx : 0
                let txDiff = totalTx > previousNetworkBytes.tx ? totalTx - previousNetworkBytes.tx : 0
                net.receivedBytesPerSec = UInt64(Double(rxDiff) / elapsed)
                net.sentBytesPerSec = UInt64(Double(txDiff) / elapsed)
            }
        }

        previousNetworkBytes = (totalRx, totalTx)
        previousTimestamp = now
    }

    // MARK: - GPU

    private func sampleGPU(_ gpu: inout GPUMetrics) {
        // Use IOKit to get GPU info
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            gpu.name = "Apple GPU"
            return
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Get GPU name
            if let name = dict["CFBundleIdentifier"] as? String {
                if name.contains("Apple") {
                    gpu.name = "Apple Silicon GPU"
                } else {
                    gpu.name = name
                }
            }

            // Performance statistics
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                if let utilization = perfStats["Device Utilization %"] as? Int {
                    gpu.utilizationPercent = Double(utilization)
                } else if let utilization = perfStats["GPU Activity(%)"] as? Int {
                    gpu.utilizationPercent = Double(utilization)
                }

                if let vramUsed = perfStats["vramUsedBytes"] as? UInt64 {
                    gpu.vramUsed = vramUsed
                }
                if let vramFree = perfStats["vramFreeBytes"] as? UInt64 {
                    gpu.vramTotal = gpu.vramUsed + vramFree
                }
                // Try alternate keys for Apple Silicon
                if let inUse = perfStats["In use system memory"] as? UInt64 {
                    gpu.vramUsed = inUse
                }
                if let alloc = perfStats["Alloc system memory"] as? UInt64 {
                    gpu.vramTotal = alloc
                }
            }

            break // Just get first GPU
        }

        if gpu.name == "Unknown" {
            gpu.name = "Apple GPU"
        }
    }

    // MARK: - Top Processes

    private func sampleTopProcesses(limit: Int) -> [ProcessInfo] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return [] }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var processes: [ProcessInfo] = []

        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }

            var name = proc.kp_proc.p_comm
            let processName = withUnsafePointer(to: &name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }

            // Get memory info via task_info
            var taskInfo = mach_task_basic_info()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
            )

            var memBytes: UInt64 = 0

            var task: mach_port_t = 0
            if task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS {
                let result = withUnsafeMutablePointer(to: &taskInfo) { ptr in
                    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { intPtr in
                        task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &infoCount)
                    }
                }
                if result == KERN_SUCCESS {
                    memBytes = UInt64(taskInfo.resident_size)
                }
                mach_port_deallocate(mach_task_self_, task)
            }

            if memBytes > 1_000_000 {  // Only show processes using > 1MB
                processes.append(ProcessInfo(
                    id: pid,
                    name: processName,
                    cpuPercent: 0,
                    memoryBytes: memBytes
                ))
            }
        }

        // Sort by memory usage descending
        processes.sort { $0.memoryBytes > $1.memoryBytes }
        return Array(processes.prefix(limit))
    }
}
