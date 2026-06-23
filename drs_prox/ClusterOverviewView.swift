import SwiftUI
import Combine

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ClusterOverviewView: View {
    @EnvironmentObject var viewModel: ClusterViewModel
    @Environment(\.windowScale) private var s
    @State private var showMaintenanceSheet = false
    @State private var uniformCardHeight: CGFloat?
    @State private var nodeToUpdate: String?
    @State private var showUpdateWarning = false
    @State private var nextRefreshDate: Date?
    @State private var refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                    // Auto-refresh indicator
                    if viewModel.settings.autoRefreshInterval != .off, let nextRefresh = nextRefreshDate {
                        let remaining = Int(nextRefresh.timeIntervalSinceNow)
                        if remaining > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(remaining)s")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Nächste automatische Aktualisierung in \(remaining) Sekunden")
                        }
                    }
                    
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
                        Task { 
                            await viewModel.refresh()
                            updateNextRefreshDate()
                        }
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
            .onReceive(refreshTimer) { _ in
                updateNextRefreshDate()
            }
            .onAppear {
                updateNextRefreshDate()
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
        .alert("Neustart erforderlich", isPresented: $showUpdateWarning, presenting: nodeToUpdate) { nodeName in
            Button("Abbrechen", role: .cancel) { nodeToUpdate = nil }
            Button("Trotzdem installieren", role: .destructive) {
                Task { await viewModel.installUpdates(for: nodeName) }
                nodeToUpdate = nil
            }
        } message: { nodeName in
            Text("Nach dem Einspielen der Updates auf \"\(nodeName)\" ist ein Neustart erforderlich. Laufende VMs auf diesem Host könnten beeinträchtigt werden.")
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
                            updateInfo: viewModel.nodeUpdates[node.name],
                            fixedHeight: uniformCardHeight,
                            updateProgress: viewModel.nodeUpdateProgress[node.name] ?? .idle,
                            onMaintenance: {
                                viewModel.startMaintenance(for: node.name)
                                showMaintenanceSheet = true
                            },
                            onInstallUpdates: {
                                if viewModel.nodeUpdates[node.name]?.rebootRequired == true {
                                    nodeToUpdate = node.name
                                    showUpdateWarning = true
                                } else {
                                    Task { await viewModel.installUpdates(for: node.name) }
                                }
                            }
                        )
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: CardHeightKey.self,
                                value: geo.size.height
                            )
                        })
                    }
                }
                .onPreferenceChange(CardHeightKey.self) { h in
                    if h > 0 { uniformCardHeight = h }
                }
            }
            .padding(16 * s)
        }
    }
    
    private func updateNextRefreshDate() {
        guard let interval = viewModel.settings.autoRefreshInterval.seconds,
              let lastRefresh = viewModel.lastRefresh else {
            nextRefreshDate = nil
            return
        }
        nextRefreshDate = lastRefresh.addingTimeInterval(interval)
    }
}

struct NodeCard: View {
    let node: ProxmoxNode
    let vms: [ProxmoxVM]
    let updateInfo: NodeUpdateInfo?
    var fixedHeight: CGFloat? = nil
    var updateProgress: NodeUpdateProgress = .idle
    let onMaintenance: () -> Void
    var onInstallUpdates: () -> Void = {}
    @State private var isExpanded = true
    @Environment(\.windowScale) private var s

    private var showUpdateSection: Bool {
        (updateInfo?.hasUpdates ?? false) || updateProgress != .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            header
            resourceBars
            if !node.networkInterfaces.isEmpty {
                Divider()
                NetworkInterfaceView(interfaces: node.networkInterfaces)
            }
            if showUpdateSection {
                Divider()
                updateSection
            }
            if isExpanded && !vms.isEmpty {
                Divider()
                vmList
            }
            
            // Spacer to push content to the top when card is stretched
            Spacer(minLength: 0)
        }
        .padding(14 * s)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, alignment: .top)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14 * s))
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updateProgress {
        case .idle:
            if let info = updateInfo, info.hasUpdates, node.isOnline {
                HStack {
                    Label("\(info.updateCount) Update\(info.updateCount == 1 ? "" : "s") verfügbar",
                          systemImage: "arrow.down.circle")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Installieren") { onInstallUpdates() }
                        .font(.system(size: 11 * s, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .installing:
            HStack {
                Label("Updates werden installiert...", systemImage: "arrow.down.circle")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.blue)
                Spacer()
                ProgressView().controlSize(.small)
            }
        case .completed:
            Label("Updates erfolgreich installiert", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11 * s))
                .foregroundStyle(.green)
        case .failed(let msg):
            Label("Fehler: \(msg)", systemImage: "xmark.circle.fill")
                .font(.system(size: 11 * s))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var header: some View {
        HStack(spacing: 8 * s) {
            Circle()
                .fill(node.isOnline ? Color.green : Color.red)
                .frame(width: 10 * s, height: 10 * s)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 15 * s, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(node.isOnline ? "Online" : "Offline")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(node.isOnline ? Color.green : Color.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4 * s)
            
            VStack(alignment: .trailing, spacing: 2 * s) {
                Text("\(vms.count) VM\(vms.count == 1 ? "" : "s")")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4 * s) {
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
        }
        .frame(minHeight: 40 * s)
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
        VStack(spacing: 1 * s) {
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
        HStack(spacing: 6 * s) {
            Image(systemName: vm.isRunning ? "play.circle.fill" : "stop.circle.fill")
                .font(.system(size: 9 * s))
                .foregroundStyle(vm.isRunning ? Color.green : Color.gray)
            Text(vm.displayName)
                .font(.system(size: 11 * s))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer()
            if vm.isRunning {
                Text(String(format: "%.0f%%", vm.cpuUsage * 100))
                    .font(.system(size: 9 * s))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("ID \(vm.id)")
                .font(.system(size: 9 * s))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 0)
    }
}
