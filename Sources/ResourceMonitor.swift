import Darwin
import Foundation

/// Totals for one Chrome instance: the browser process plus all its helpers.
struct ProcessTreeUsage {
    var memory: UInt64 = 0      // physical footprint, bytes
    var cpuTime: UInt64 = 0     // user + system, nanoseconds since start
    var pids: [pid_t] = []
    var stopped = false         // main process is frozen with SIGSTOP
}

/// What the UI shows for a running profile.
struct ProfileUsage: Equatable {
    var memoryMB: Int
    var cpuPercent: Int
    var processes: Int
    var frozen: Bool

    var memoryText: String { ProfileUsage.format(memoryMB) }

    static func format(_ mb: Int) -> String {
        mb < 1024 ? "\(mb) МБ" : String(format: "%.1f ГБ", Double(mb) / 1024)
    }
}

/// Reads per-process memory and CPU straight from the kernel (libproc) —
/// no `ps` subprocess, well under a millisecond per sample.
enum ResourceMonitor {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func snapshot(roots: [UUID: pid_t]) -> [UUID: ProcessTreeUsage] {
        guard !roots.isEmpty else { return [:] }

        var all = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&all, Int32(all.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [:] }

        var children: [pid_t: [pid_t]] = [:]
        var status: [pid_t: UInt32] = [:]
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        for pid in all.prefix(count) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { continue }
            children[pid_t(info.pbi_ppid), default: []].append(pid)
            status[pid] = info.pbi_status
        }

        var result: [UUID: ProcessTreeUsage] = [:]
        for (id, root) in roots {
            guard let rootStatus = status[root] else { continue }
            var usage = ProcessTreeUsage()
            usage.stopped = rootStatus == 4   // SSTOP
            var queue = [root]
            while let pid = queue.popLast() {
                usage.pids.append(pid)
                queue.append(contentsOf: children[pid] ?? [])
                var ri = rusage_info_v2()
                let ok = withUnsafeMutablePointer(to: &ri) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                    }
                }
                guard ok == 0 else { continue }
                usage.memory += ri.ri_phys_footprint
                usage.cpuTime += (ri.ri_user_time + ri.ri_system_time) * timebase.numer / timebase.denom
            }
            result[id] = usage
        }
        return result
    }
}
