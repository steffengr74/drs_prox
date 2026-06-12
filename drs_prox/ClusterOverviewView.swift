import SwiftUI

struct ClusterOverviewView: View {
    @EnvironmentObject var viewModel: ClusterViewModel
    @Environment(\.windowScale) private var s
    @State private var showMaintenanceSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.nodes.isEmpty {
                    ProgressView("Lade Cluster-Daten...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.nodes.isEmpty {
                    emptyState
                } else {
                    nodeList
                }
            }
            .navigationTitle("Proxmox Cluster")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refreshUpdates() }
                    } label: {
                        if viewModel.isCheckingUpdates {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Updates prüfen", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(viewModel.isCheckingUpdates || viewModel.nodes.isEmpty)
                    .help("Updates auf allen Hosts prüfen")

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .help("Cluster-Daten neu laden")
                }
            }
        }
        .sheet(isPresented: $showMaintenanceSheet, onDismiss: {
            if !viewModel.isMaintenanceRunning {
                viewModel.cancelMaintenance()
            }
        }) {
            if let nodeName = viewModel.evacuatingNode {
                MaintenanceSheet(nodeName: nodeName)
                    .environmentObject(viewModel)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16 * s) {
            Image(systemName: viewModel.errorMessage != nil ? "exclamationmark.triangle" : "server.rack")
                .font(.system(size: 52 * s))
                .foregroundStyle(viewModel.errorMessage != nil ? Color.orange : Color.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13 * s))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Text("Einstellungen konfigurieren und Daten laden")
                    .font(.system(size: 13 * s))
                    .foregroundStyle(.secondary)
            }
            Button("Aktualisieren") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading || !viewModel.settings.isConfigured)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var nodeList: some View {
        ScrollView {
            VStack(spacing: 10 * s) {
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.system(size: 11 * s))
                    }
                    .foregroundStyle(.orange)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 360))],
                    spacing: 12 * s
                ) {
                    ForEach(viewModel.nodes) { node in
                        NodeCard(
                            node: node,
                            vms: viewModel.vms(for: node),
                            updateInfo: viewModel.nodeUpdates[node.name]
                        ) {
                            viewModel.startMaintenance(for: node.name)
                            showMaintenanceSheet = true
                        }
                    }
                }
            }
            .padding(16 * s)
        }
    }
}

struct NodeCard: View {
    let node: ProxmoxNode
    let vms: [ProxmoxVM]
    let updateInfo: NodeUpdateInfo?
    let onMaintenance: () -> Void
    @State private var isExpanded = true
    @Environment(\.windowScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            header
            resourceBars
            if isExpanded && !vms.isEmpty {
                Divider()
                vmList
            }
        }
        .padding(14 * s)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14 * s))
    }

    private var header: some View {
        HStack(spacing: 8 * s) {
            Circle()
                .fill(node.isOnline ? Color.green : Color.red)
                .frame(width: 10 * s, height: 10 * s)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 15 * s, weight: .semibold))
                Text(node.isOnline ? "Online" : "Offline")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(node.isOnline ? Color.green : Color.red)
            }
            Spacer()
            Text("\(vms.count) VM\(vms.count == 1 ? "" : "s")")
                .font(.system(size: 11 * s))
                .foregroundStyle(.secondary)

            // Update count badge
            if let info = updateInfo, info.hasUpdates {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10 * s))
                    Text("\(info.updateCount)")
                        .font(.system(size: 10 * s, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * s)
                .padding(.vertical, 3 * s)
                .background(Color.orange)
                .clipShape(Capsule())
                .help("\(info.updateCount) Update\(info.updateCount == 1 ? "" : "s") verfügbar")
            }

            // Reboot required badge
            if let info = updateInfo, info.rebootRequired {
                HStack(spacing: 3) {
                    Image(systemName: "restart.circle.fill")
                        .font(.system(size: 10 * s))
                    Text("Neustart")
                        .font(.system(size: 10 * s, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * s)
                .padding(.vertical, 3 * s)
                .background(Color.red)
                .clipShape(Capsule())
                .help("Neustart nach Updates erforderlich")
            }

            // Maintenance mode button
            if node.isOnline {
                Button {
                    onMaintenance()
                } label: {
                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Wartungsmodus: Alle VMs von diesem Host evakuieren")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var resourceBars: some View {
        VStack(spacing: 8 * s) {
            ResourceBar(
                label: "CPU",
                value: node.cpuUsage,
                detail: String(format: "%.1f%%", node.cpuUsage * 100),
                color: loadColor(node.cpuUsage)
            )
            ResourceBar(
                label: "RAM",
                value: node.memUsagePercent,
                detail: "\(ProxmoxNode.formatBytes(node.memUsed)) / \(ProxmoxNode.formatBytes(node.memTotal))",
                color: loadColor(node.memUsagePercent)
            )
        }
    }

    private var vmList: some View {
        VStack(spacing: 2 * s) {
            ForEach(vms) { vm in
                VMRow(vm: vm)
            }
        }
    }

    private func loadColor(_ value: Double) -> Color {
        if value > 0.8 { return .red }
        if value > 0.6 { return .orange }
        return .green
    }
}

struct ResourceBar: View {
    let label: String
    let value: Double
    let detail: String
    let color: Color
    @Environment(\.windowScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack {
                Text(label)
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.system(size: 11 * s))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * max(0, min(value, 1.0)))
                        .animation(.easeInOut, value: value)
                }
            }
            .frame(height: 7 * s)
        }
    }
}

struct VMRow: View {
    let vm: ProxmoxVM
    @Environment(\.windowScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: vm.isRunning ? "play.circle.fill" : "stop.circle.fill")
                .font(.system(size: 11 * s))
                .foregroundStyle(vm.isRunning ? Color.green : Color.gray)
            Text(vm.displayName)
                .font(.system(size: 13 * s))
            Spacer()
            if vm.isRunning {
                Text(String(format: "%.0f%%", vm.cpuUsage * 100))
                    .font(.system(size: 10 * s))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("ID \(vm.id)")
                .font(.system(size: 10 * s))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1 * s)
    }
}
