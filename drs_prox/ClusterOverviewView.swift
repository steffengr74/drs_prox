import SwiftUI

struct ClusterOverviewView: View {
    @EnvironmentObject var viewModel: ClusterViewModel
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
                ToolbarItem(placement: .automatic) {
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
        VStack(spacing: 16) {
            Image(systemName: viewModel.errorMessage != nil ? "exclamationmark.triangle" : "server.rack")
                .font(.system(size: 52))
                .foregroundStyle(viewModel.errorMessage != nil ? Color.orange : Color.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Text("Einstellungen konfigurieren und Daten laden")
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
            LazyVStack(spacing: 12) {
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                }
                ForEach(viewModel.nodes) { node in
                    NodeCard(node: node, vms: viewModel.vms(for: node)) {
                        viewModel.startMaintenance(for: node.name)
                        showMaintenanceSheet = true
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct NodeCard: View {
    let node: ProxmoxNode
    let vms: [ProxmoxVM]
    let onMaintenance: () -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            resourceBars
            if isExpanded && !vms.isEmpty {
                Divider()
                vmList
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(node.isOnline ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.headline)
                Text(node.isOnline ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundStyle(node.isOnline ? Color.green : Color.red)
            }
            Spacer()
            Text("\(vms.count) VM\(vms.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Maintenance mode button
            if node.isOnline {
                Button {
                    onMaintenance()
                } label: {
                    Image(systemName: "wrench.adjustable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Wartungsmodus: Alle VMs von diesem Host evakuieren")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var resourceBars: some View {
        VStack(spacing: 8) {
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
        VStack(spacing: 2) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.caption)
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
            .frame(height: 7)
        }
    }
}

struct VMRow: View {
    let vm: ProxmoxVM

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.isRunning ? "play.circle.fill" : "stop.circle.fill")
                .font(.caption)
                .foregroundStyle(vm.isRunning ? Color.green : Color.gray)
            Text(vm.displayName)
                .font(.subheadline)
            Spacer()
            if vm.isRunning {
                Text(String(format: "%.0f%%", vm.cpuUsage * 100))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("ID \(vm.id)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}
