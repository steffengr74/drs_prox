import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject var viewModel: ClusterViewModel

    private var pendingRecs: [MigrationRecommendation] {
        viewModel.recommendations.filter { $0.migrationStatus == .pending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.nodes.isEmpty {
                    noDataState
                } else if viewModel.recommendations.isEmpty {
                    balancedState
                } else {
                    recList
                }
            }
            .navigationTitle("DRS Empfehlungen")
            .toolbar {
                if pendingRecs.count > 1 {
                    ToolbarItem(placement: .automatic) {
                        Button("Alle migrieren (\(pendingRecs.count))") {
                            Task { await viewModel.migrateAll() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var noDataState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Zuerst Cluster-Daten laden")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var balancedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Cluster ist ausgeglichen")
                .font(.headline)
            Text("Keine Migrationsempfehlungen erforderlich.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recList: some View {
        List(viewModel.recommendations) { rec in
            RecommendationRow(rec: rec)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
    }
}

struct RecommendationRow: View {
    let rec: MigrationRecommendation
    @EnvironmentObject var viewModel: ClusterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                PriorityBadge(priority: rec.priority)
                Text(rec.vm.displayName).font(.headline)
                Spacer()
                Text("VM \(rec.vm.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "server.rack").font(.caption).foregroundStyle(.red)
                Text(rec.fromNode).font(.subheadline).foregroundStyle(.red)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "server.rack").font(.caption).foregroundStyle(.green)
                Text(rec.toNode).font(.subheadline).foregroundStyle(.green)
            }

            Text(rec.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                MigrationStatusLabel(status: rec.migrationStatus)
                Spacer()
                migrateButton
            }
        }
    }

    @ViewBuilder
    private var migrateButton: some View {
        if rec.migrationStatus == .pending {
            Button("Migrieren") {
                Task { await viewModel.migrate(rec) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else if rec.migrationStatus == .running {
            ProgressView().controlSize(.small)
        }
    }
}

struct PriorityBadge: View {
    let priority: MigrationRecommendation.Priority

    private var color: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var body: some View {
        Text(priority.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct MigrationStatusLabel: View {
    let status: MigrationRecommendation.MigrationStatus

    private var color: Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .foregroundStyle(color)
    }
}
