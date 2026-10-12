//
//  ProcessCostProbe.swift
//  Unveil
//

import Darwin
import Foundation
import Synchronization

/// ProcessCostProbe reads what the process has spent so far: CPU time (`getrusage`, which keeps the
/// time of threads that ended), CPU time per live thread, and the kernel's power counters
/// (`task_power_info_v2`: `task_energy` in nanojoules, `task_gpu_utilisation`, wakeups). Two samples
/// make a report (`delta`), which the E0 measurements print as one `COST` line.
///
/// `task_energy` is read as nanojoules (the SDK's `ri_energy_nj` is the same counter family). It looks
/// like a CPU-side estimate that scales with clock and CPU time, with no sign of GPU energy in it, so
/// use it for comparisons only. A run that reads 0 is reported as unavailable, not as zero joules.
nonisolated enum ProcessCostProbe {

    /// Sample is the counters at one instant. `threads` is keyed by the kernel's thread id.
    struct Sample: Sendable {

        let uptimeNs      : UInt64
        let cpuUserNs     : UInt64
        let cpuSystemNs   : UInt64
        let energyNj      : UInt64
        let gpuBusy       : UInt64
        let wakeups       : UInt64
        let threads       : [UInt64: ThreadTime]
    }

    struct ThreadTime: Sendable {

        let name  : String
        let cpuNs : UInt64
    }

    private static let mainPort = Mutex<mach_port_t>(0)

    /// registerMainThread remembers the calling thread as "main" in the per-thread report.
    static func registerMainThread() {
        let port = pthread_mach_thread_np(pthread_self())
        mainPort.withLock { $0 = port }
    }

    static func uptimeNs() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    static func sample() -> Sample {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        let power = taskPower()

        return Sample(
            uptimeNs    : uptimeNs(),
            cpuUserNs   : nanoseconds(of: usage.ru_utime),
            cpuSystemNs : nanoseconds(of: usage.ru_stime),
            energyNj    : power?.task_energy ?? 0,
            gpuBusy     : power?.gpu_energy.task_gpu_utilisation ?? 0,
            wakeups     : (power?.cpu_energy.task_interrupt_wakeups ?? 0)
                + (power?.cpu_energy.task_platform_idle_wakeups ?? 0),
            threads     : liveThreads()
        )
    }

    /// delta is the report of what the process spent between two samples, as a JSON-ready dictionary.
    /// Threads are compared only when both samples have them: a worker that started or ended in
    /// between is inside `cpuMs` (rusage) but not in `threadsCpuMs`.
    static func delta(from start: Sample, to end: Sample) -> [String: Any] {
        func ms(_ later: UInt64, _ earlier: UInt64) -> Double {
            Double(later &- earlier) / 1_000_000
        }

        var threads = [String: Double]()

        for (identifier, now) in end.threads {
            guard let before = start.threads[identifier] else { continue }

            threads[now.name, default: 0] += ms(now.cpuNs, before.cpuNs)
        }

        let wall   = ms(end.uptimeNs, start.uptimeNs)
        let cpu    = ms(end.cpuUserNs, start.cpuUserNs) + ms(end.cpuSystemNs, start.cpuSystemNs)
        let energy = end.energyNj &- start.energyNj

        var report: [String: Any] = [
            "wallMs"         : wall,
            "cpuMs"          : cpu,
            "cpuUserMs"      : ms(end.cpuUserNs, start.cpuUserNs),
            "cpuSystemMs"    : ms(end.cpuSystemNs, start.cpuSystemNs),
            "cpuCores"       : wall > 0 ? cpu / wall : 0,
            "threadsCpuMs"   : threads,
            "gpuBusyRaw"     : end.gpuBusy &- start.gpuBusy,
            "wakeups"        : end.wakeups &- start.wakeups,
            "energyAvailable": end.energyNj > 0,
        ]

        if end.energyNj > 0 {
            report["energyMj"] = Double(energy) / 1_000_000
            report["powerMw"]  = wall > 0 ? Double(energy) / 1_000_000 / (wall / 1000) : 0
        }

        return report
    }

    private static func nanoseconds(of time: timeval) -> UInt64 {
        UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_usec) * 1000
    }

    private static func taskPower() -> task_power_info_v2_data_t? {
        var info  = task_power_info_v2_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2_data_t>.size / MemoryLayout<natural_t>.size)

        // task_info fills `count` words of the struct it was given; `count` is its size in words.
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { words in
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), words, &count)
            }
        }

        return status == KERN_SUCCESS ? info : nil
    }

    /// liveThreads lists the process's threads with their CPU time and name.
    private static func liveThreads() -> [UInt64: ThreadTime] {
        var list : thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [:] }

        defer {
            for index in 0 ..< Int(count) {
                mach_port_deallocate(mach_task_self_, list[index])
            }

            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: list)),
                vm_size_t(Int(count) * MemoryLayout<thread_t>.size)
            )
        }

        let main    = mainPort.withLock { $0 }
        var threads = [UInt64: ThreadTime]()

        for index in 0 ..< Int(count) {
            let port = list[index]

            var identifier = thread_identifier_info_data_t()
            var idCount    = mach_msg_type_number_t(
                MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size
            )
            var basic      = thread_basic_info_data_t()
            var basicCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
            )

            let idStatus = withUnsafeMutablePointer(to: &identifier) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(idCount)) { words in
                    thread_info(port, thread_flavor_t(THREAD_IDENTIFIER_INFO), words, &idCount)
                }
            }

            let basicStatus = withUnsafeMutablePointer(to: &basic) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { words in
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), words, &basicCount)
                }
            }

            guard idStatus == KERN_SUCCESS, basicStatus == KERN_SUCCESS else { continue }

            let user   = UInt64(basic.user_time.seconds) * 1_000_000_000 + UInt64(basic.user_time.microseconds) * 1000
            let system = UInt64(basic.system_time.seconds) * 1_000_000_000 + UInt64(basic.system_time.microseconds) * 1000

            threads[identifier.thread_id] = ThreadTime(
                name  : port == main ? "main" : name(of: port),
                cpuNs : user + system
            )
        }

        return threads
    }

    private static func name(of port: thread_t) -> String {
        guard let thread = pthread_from_mach_thread_np(port) else { return "other" }

        var buffer = [CChar](repeating: 0, count: 64)
        pthread_getname_np(thread, &buffer, buffer.count)

        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "other" : name
    }
}
