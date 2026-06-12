import Foundation

struct ProxmoxNode: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let cpuUsage: Double
    let maxCPU: Int
    let memTotal: Int64
    let memUsed: Int64
    let uptime: Int

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

    var baseURL: String {
        "https://\(host):\(port)/api2/json"
    }

    var isConfigured: Bool {
        !host.isEmpty && !tokenID.isEmpty && !tokenSecret.isEmpty
    }
}
