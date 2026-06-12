import SwiftUI

struct MaintenanceSheet: View {
    let nodeName: String
    @EnvironmentObject var viewModel: ClusterViewModel
    @Environment(\.dismiss) private var dismiss

    private var migrations: [MigrationRecommendation] { viewModel.maintenanceMigrations }
    private var pendingCount: Int { migrations.filter { $0.migrationStatus == .pending }.count }
    private var completedCount: Int { migrations.filter { $0.migrationStatus == .completed }.count }
    private var failedCount: Int {
        migrations.filter {
            if case .failed = $0.migrationStatus { return true }
            return false
        }.count
    }
    private var isAllDone: Bool {
        !migrations.isEmpty && migrations.allSatisfy { $0.migrationStatus.isDone }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if migrations.isEmpty {
                emptyState
            } else {
                migrationList
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 380, idealHeight: 480)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "wrench.adjustable.fill")
                .font(.title)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Wartungsmodus")
                    .font(.headline)
                Text("Alle laufenden VMs von \(nodeName) evakuieren")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !migrations.isEmpty {
                HStack(spacing: 14) {
                    statBadge(count: completedCount, icon: "checkmark.circle.fill", color: .green)
                    statBadge(count: failedCount, icon: "xmark.circle.fill", color: .red)
                    statBadge(count: pendingCount, icon: "clock", color: .secondary)
                }
            }
        }
        .padding()
    }

    private func statBadge(count: Int, icon: String, color: Color) -> some View {
        Label("\(count)", systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var migrationList: some View {
        List(migrations) { rec in
            MaintenanceMigrationRow(rec: rec)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Keine laufenden VMs auf \(nodeName)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Schließen") {
                viewModel.cancelMaintenance()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.isMaintenanceRunning)

            Spacer()

            if isAllDone {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Alle Migrationen abgeschlossen")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else if !migrations.isEmpty {
                Button {
                    Task { await viewModel.executeMaintenanceMigrations() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isMaintenanceRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        Text(viewModel.isMaintenanceRunning
                             ? "Wird migriert..."
                             : "\(migrations.count) VM\(migrations.count == 1 ? "" : "s") migrieren")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isMaintenanceRunning || pendingCount == 0)
            }
        }
        .padding()
    }
}

// MARK: - Row

struct MaintenanceMigrationRow: View {
    let rec: MigrationRecommendation

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rec.vm.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("VM \(rec.vm.id) · \(ProxmoxNode.formatBytes(rec.vm.maxMem)) RAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(rec.toNode)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            MigrationStatusLabel(status: rec.migrationStatus)
                .frame(width: 110, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch rec.migrationStatus {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
