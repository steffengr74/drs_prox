import Foundation

struct DRSEngine {
    static let overloadThreshold: Double = 0.70
    static let underloadThreshold: Double = 0.40
    static let imbalanceThreshold: Double = 0.15

    func generateRecommendations(nodes: [ProxmoxNode], vms: [ProxmoxVM]) -> [MigrationRecommendation] {
        let onlineNodes = nodes.filter { $0.isOnline }
        guard onlineNodes.count >= 2 else { return [] }

        let runningVMs = vms.filter { $0.isRunning }
        var recommendations: [MigrationRecommendation] = []
        var usedVMIDs: Set<Int> = []

        let sorted = onlineNodes.sorted { $0.loadScore > $1.loadScore }
        let overloaded = sorted.filter { $0.loadScore > Self.overloadThreshold }
        let underloaded = sorted.filter { $0.loadScore < Self.underloadThreshold }

        // Overload relief: move VMs from hot nodes to cool nodes
        for source in overloaded {
            let nodeVMs = runningVMs
                .filter { $0.node == source.name && !usedVMIDs.contains($0.id) }
                .sorted { $0.maxMem > $1.maxMem }

            for target in underloaded where target.id != source.id {
                for vm in nodeVMs {
                    guard source.memTotal > 0 else { continue }
                    let memFraction = Double(vm.maxMem) / Double(source.memTotal)
                    let projectedSourceRAM = source.memUsagePercent - memFraction
                    let projectedTargetRAM = target.memUsagePercent + memFraction

                    guard projectedSourceRAM < Self.overloadThreshold,
                          projectedTargetRAM < Self.overloadThreshold else { continue }

                    let diff = source.loadScore - target.loadScore
                    let priority: MigrationRecommendation.Priority = diff > 0.4 ? .high : diff > 0.25 ? .medium : .low
                    recommendations.append(MigrationRecommendation(
                        vm: vm,
                        fromNode: source.name,
                        toNode: target.name,
                        reason: makeReason(source: source, target: target),
                        priority: priority
                    ))
                    usedVMIDs.insert(vm.id)
                    break
                }
            }
        }

        // Balance pass: suggest migrations even without overload when imbalance exists
        if recommendations.isEmpty {
            let avgLoad = onlineNodes.map(\.loadScore).reduce(0, +) / Double(onlineNodes.count)
            let heavy = sorted.filter { $0.loadScore > avgLoad + Self.imbalanceThreshold }
            let light = sorted.filter { $0.loadScore < avgLoad - Self.imbalanceThreshold }

            for source in heavy {
                let nodeVMs = runningVMs
                    .filter { $0.node == source.name && !usedVMIDs.contains($0.id) }
                    .sorted { $0.maxMem > $1.maxMem }

                guard let vm = nodeVMs.first else { continue }

                for target in light where target.id != source.id {
                    let reason = String(format: "Lastausgleich: %@ %.0f%% → %@ %.0f%%",
                        source.name, source.loadScore * 100,
                        target.name, target.loadScore * 100)
                    recommendations.append(MigrationRecommendation(
                        vm: vm,
                        fromNode: source.name,
                        toNode: target.name,
                        reason: reason,
                        priority: .low
                    ))
                    usedVMIDs.insert(vm.id)
                    break
                }
            }
        }

        return recommendations.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }

    // Distribute all running VMs from a node to the remaining hosts (maintenance mode)
    func maintenanceMigrations(evacuate nodeName: String, nodes: [ProxmoxNode], vms: [ProxmoxVM]) -> [MigrationRecommendation] {
        let targets = nodes.filter { $0.isOnline && $0.name != nodeName }
        guard !targets.isEmpty else { return [] }

        let nodeVMs = vms.filter { $0.node == nodeName && $0.isRunning }
        guard !nodeVMs.isEmpty else { return [] }

        // Track projected RAM per target as we assign VMs
        var projectedUsed: [String: Int64] = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.name, $0.memUsed) }
        )

        var result: [MigrationRecommendation] = []

        // Best-fit decreasing: largest VMs first for better packing
        for vm in nodeVMs.sorted(by: { $0.maxMem > $1.maxMem }) {
            // Pick target with most free RAM that can still fit the VM
            let best = targets
                .sorted {
                    let aFree = $0.memTotal - (projectedUsed[$0.name] ?? $0.memUsed)
                    let bFree = $1.memTotal - (projectedUsed[$1.name] ?? $1.memUsed)
                    return aFree > bFree
                }
                .first {
                    let free = $0.memTotal - (projectedUsed[$0.name] ?? $0.memUsed)
                    return free >= vm.maxMem
                }
                // Fallback: node with most free RAM regardless of capacity
                ?? targets.max {
                    let aFree = $0.memTotal - (projectedUsed[$0.name] ?? $0.memUsed)
                    let bFree = $1.memTotal - (projectedUsed[$1.name] ?? $1.memUsed)
                    return aFree < bFree
                }

            guard let target = best else { continue }

            projectedUsed[target.name] = (projectedUsed[target.name] ?? target.memUsed) + vm.maxMem

            let freeAfter = target.memTotal - (projectedUsed[target.name] ?? 0)
            let reason = "Wartungsmodus · Ziel: \(target.name) · Frei danach: \(ProxmoxNode.formatBytes(max(0, freeAfter)))"

            result.append(MigrationRecommendation(
                vm: vm,
                fromNode: nodeName,
                toNode: target.name,
                reason: reason,
                priority: .high
            ))
        }

        return result
    }

    private func makeReason(source: ProxmoxNode, target: ProxmoxNode) -> String {
        String(format: "%@ CPU %.0f%% RAM %.0f%% → %@ CPU %.0f%% RAM %.0f%%",
            source.name, source.cpuUsage * 100, source.memUsagePercent * 100,
            target.name, target.cpuUsage * 100, target.memUsagePercent * 100)
    }
}
