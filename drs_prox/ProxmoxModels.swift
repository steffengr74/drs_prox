import Foundation
import SwiftUI

struct ProxmoxNode: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let cpuUsage: Double
    let maxCPU: Int
    let memTotal: Int64
    let memUsed: Int64
    let uptime: Int
    var networkInterfaces: [NetworkInterface] = []

    var memUsagePercent: Double {
        guard memTotal > 0 else { return 0 }
        return Double(memUsed) / Double(memTotal)
    }

    var isOnline: Bool { status == "online" }

    // Weighted load score: 50% CPU + 50% RAM
    var loadScore: Double {
        cpuUsage * 0.5 + memUsagePercent * 0.5
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
    
    static func formatBytesPerSecond(_ bytesPerSec: Int64) -> String {
        let mbps = Double(bytesPerSec) * 8 / 1_000_000
        if mbps >= 1000 {
            return String(format: "%.2f Gbit/s", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbit/s", mbps)
        } else {
            return String(format: "%.0f Kbit/s", mbps * 1000)
        }
    }
}

struct NetworkInterface: Identifiable, Hashable {
    let id: String  // interface name (e.g., "eno1", "eth0", "bond0")
    let name: String
    let rxBytes: Int64  // received bytes/sec
    let txBytes: Int64  // transmitted bytes/sec
    let speed: Int64?   // link speed in Mbit/s (e.g., 1000 for 1 Gbit/s)
    let isActive: Bool
    let kind: Kind
    let slaves: [String]      // bond members (for bonds)
    let bondMaster: String?   // name of bond this nic belongs to, if any

    enum Kind: String, Hashable {
        case physical
        case bond
    }

    var isBond: Bool { kind == .bond }

    // Hardcoded role mapping for this cluster's wiring scheme
    var role: String? {
        switch name {
        case "bond0": return "NFS"
        case "bond1": return "VM-Daten"
        case "nic0": return "Cluster-Link"
        case "nic1": return "Management"
        default: return nil
        }
    }

    var totalBytesPerSec: Int64 {
        rxBytes + txBytes
    }

    var utilizationPercent: Double {
        guard let linkSpeed = speed, linkSpeed > 0 else { return 0 }
        let bitsPerSec = Double(totalBytesPerSec) * 8
        let linkBitsPerSec = Double(linkSpeed) * 1_000_000
        return min(bitsPerSec / linkBitsPerSec, 1.0)
    }

    var utilizationColor: Color {
        let util = utilizationPercent
        if util > 0.8 { return .red }
        if util > 0.6 { return .orange }
        if util > 0.3 { return .yellow }
        return .green
    }
}

struct ProxmoxVM: Identifiable, Hashable {
    let id: Int
    let name: String
    let status: String
    let node: String
    let cpuUsage: Double
    let maxCPU: Int
    let memUsed: Int64
    let maxMem: Int64
    let uptime: Int

    var isRunning: Bool { status == "running" }

    var memUsagePercent: Double {
        guard maxMem > 0 else { return 0 }
        return Double(memUsed) / Double(maxMem)
    }

    var displayName: String {
        name.isEmpty ? "VM \(id)" : name
    }
}

struct NodeUpdateInfo {
    let updateCount: Int
    let rebootRequired: Bool

    var hasUpdates: Bool { updateCount > 0 }
}

enum NodeUpdateProgress: Equatable {
    case idle
    case installing
    case completed
    case failed(String)

    var isActive: Bool { self == .installing }

    var isDone: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }

    static func == (lhs: NodeUpdateProgress, rhs: NodeUpdateProgress) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.installing, .installing), (.completed, .completed): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

struct MigrationRecommendation: Identifiable {
    let id = UUID()
    let vm: ProxmoxVM
    let fromNode: String
    let toNode: String
    let reason: String
    let priority: Priority
    var migrationStatus: MigrationStatus = .pending

    enum Priority: Int {
        case high = 1, medium = 2, low = 3

        var label: String {
            switch self {
            case .high: return "Hoch"
            case .medium: return "Mittel"
            case .low: return "Niedrig"
            }
        }
    }

    enum MigrationStatus: Equatable {
        case pending, running, completed
        case failed(String)

        var label: String {
            switch self {
            case .pending: return "Ausstehend"
            case .running: return "Wird migriert..."
            case .completed: return "Abgeschlossen"
            case .failed(let msg): return "Fehler: \(msg)"
            }
        }

        var isDone: Bool {
            switch self {
            case .completed, .failed: return true
            default: return false
            }
        }
    }
}

struct ProxmoxSettings: Codable {
    var host: String = ""
    var port: Int = 8006
    var tokenID: String = ""
    var tokenSecret: String = ""
    var verifyCertificate: Bool = false
    var autoRefreshInterval: AutoRefreshInterval = .off

    var baseURL: String {
        "https://\(host):\(port)/api2/json"
    }

    var isConfigured: Bool {
        !host.isEmpty && !tokenID.isEmpty && !tokenSecret.isEmpty
    }
}

enum AutoRefreshInterval: Int, Codable, CaseIterable {
    case off = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case twentySeconds = 20
    
    var label: String {
        switch self {
        case .off: return "Aus"
        case .fiveSeconds: return "5 Sekunden"
        case .tenSeconds: return "10 Sekunden"
        case .twentySeconds: return "20 Sekunden"
        }
    }
    
    var seconds: TimeInterval? {
        self == .off ? nil : TimeInterval(self.rawValue)
    }
}
