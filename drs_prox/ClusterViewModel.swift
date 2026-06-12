import Foundation
import SwiftUI
import Combine

@MainActor
final class ClusterViewModel: ObservableObject {
    @Published var nodes: [ProxmoxNode] = []
    @Published var vms: [ProxmoxVM] = []
    @Published var recommendations: [MigrationRecommendation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var settings: ProxmoxSettings {
        didSet {
            saveSettings()
            apiClient = nil
        }
    }

    // Update check state
    @Published var nodeUpdates: [String: NodeUpdateInfo] = [:]
    @Published var isCheckingUpdates = false

    // Maintenance mode state
    @Published var maintenanceMigrations: [MigrationRecommendation] = []
    @Published var evacuatingNode: String?
    @Published var isMaintenanceRunning = false

    private var apiClient: ProxmoxAPIClient?
    private let drsEngine = DRSEngine()
    private static let settingsKey = "proxmox_settings_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(ProxmoxSettings.self, from: data) {
            settings = saved
        } else {
            settings = ProxmoxSettings()
        }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private func client() -> ProxmoxAPIClient {
        if let c = apiClient { return c }
        let c = ProxmoxAPIClient(settings: settings)
        apiClient = c
        return c
    }

    func refresh() async {
        guard settings.isConfigured else {
            errorMessage = "Bitte zuerst Verbindungseinstellungen konfigurieren."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let c = client()
            let fetchedNodes = try await c.fetchNodes()
            var allVMs: [ProxmoxVM] = []
            for node in fetchedNodes where node.isOnline {
                let nodeVMs = (try? await c.fetchVMs(on: node.name)) ?? []
                allVMs.append(contentsOf: nodeVMs)
            }
            nodes = fetchedNodes.sorted { $0.name < $1.name }
            vms = allVMs
            recommendations = drsEngine.generateRecommendations(nodes: nodes, vms: vms)
            lastRefresh = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Fetch available updates and reboot-required status for all online nodes
    func refreshUpdates() async {
        guard settings.isConfigured, !nodes.isEmpty else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        let c = client()
        for node in nodes where node.isOnline {
            let count = (try? await c.fetchUpdateCount(node: node.name)) ?? 0
            let reboot = (try? await c.fetchRebootRequired(node: node.name)) ?? false
            nodeUpdates[node.name] = NodeUpdateInfo(updateCount: count, rebootRequired: reboot)
        }
    }

    func migrate(_ rec: MigrationRecommendation) async {
        func updateStatus(_ status: MigrationRecommendation.MigrationStatus) {
            if let idx = recommendations.firstIndex(where: { $0.id == rec.id }) {
                recommendations[idx].migrationStatus = status
            }
        }

        updateStatus(.running)

        do {
            let c = client()
            let upid = try await c.migrateVM(vmid: rec.vm.id, fromNode: rec.fromNode, toNode: rec.toNode)

            for _ in 0..<40 {
                try await Task.sleep(for: .seconds(5))
                let result = try await c.fetchTaskStatus(node: rec.fromNode, upid: upid)
                if result.isFinished {
                    updateStatus(result.isSuccess ? .completed : .failed(result.exitStatus ?? "Unbekannt"))
                    await refresh()
                    return
                }
            }
            updateStatus(.failed("Timeout nach 200 Sekunden"))
        } catch {
            updateStatus(.failed(error.localizedDescription))
        }
    }

    func migrateAll() async {
        let pending = recommendations.filter { $0.migrationStatus == .pending }
        for rec in pending {
            await migrate(rec)
        }
    }

    func vms(for node: ProxmoxNode) -> [ProxmoxVM] {
        vms.filter { $0.node == node.name }
    }

    // MARK: - Maintenance Mode

    func startMaintenance(for nodeName: String) {
        maintenanceMigrations = drsEngine.maintenanceMigrations(
            evacuate: nodeName,
            nodes: nodes,
            vms: vms
        )
        evacuatingNode = nodeName
    }

    func executeMaintenanceMigrations() async {
        isMaintenanceRunning = true
        defer { isMaintenanceRunning = false }

        let pending = maintenanceMigrations.filter { $0.migrationStatus == .pending }

        for rec in pending {
            func updateStatus(_ status: MigrationRecommendation.MigrationStatus) {
                if let idx = maintenanceMigrations.firstIndex(where: { $0.id == rec.id }) {
                    maintenanceMigrations[idx].migrationStatus = status
                }
            }

            updateStatus(.running)

            do {
                let c = client()
                let upid = try await c.migrateVM(vmid: rec.vm.id, fromNode: rec.fromNode, toNode: rec.toNode)

                var finished = false
                for _ in 0..<40 {
                    try await Task.sleep(for: .seconds(5))
                    let result = try await c.fetchTaskStatus(node: rec.fromNode, upid: upid)
                    if result.isFinished {
                        updateStatus(result.isSuccess ? .completed : .failed(result.exitStatus ?? "Unbekannt"))
                        finished = true
                        break
                    }
                }
                if !finished { updateStatus(.failed("Timeout")) }
            } catch {
                updateStatus(.failed(error.localizedDescription))
            }
        }

        await refresh()
    }

    func cancelMaintenance() {
        guard !isMaintenanceRunning else { return }
        maintenanceMigrations = []
        evacuatingNode = nil
    }
}
