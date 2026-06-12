import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject var viewModel: ClusterViewModel
    @Environment(\.windowScale) private var s

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
        VStack(spacing: 16 * s) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 52 * s))
                .foregroundStyle(.secondary)
            Text("Zuerst Cluster-Daten laden")
                .font(.system(size: 13 * s))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var balancedState: some View {
        VStack(spacing: 16 * s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52 * s))
                .foregroundStyle(.green)
            Text("Cluster ist ausgeglichen")
                .font(.system(size: 15 * s, weight: .semibold))
            Text("Keine Migrationsempfehlungen erforderlich.")
                .font(.system(size: 13 * s))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recList: some View {
        List(viewModel.recommendations) { rec in
            RecommendationRow(rec: rec)
                .listRowInsets(EdgeInsets(top: 10 * s, leading: 16 * s, bottom: 10 * s, trailing: 16 * s))
        }
        .listStyle(.plain)
    }
}

struct RecommendationRow: View {
    let rec: MigrationRecommendation
    @EnvironmentObject var viewModel: ClusterViewModel
    @Environment(\.windowScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(alignment: .center) {
                PriorityBadge(priority: rec.priority)
                Text(rec.vm.displayName)
                    .font(.system(size: 15 * s, weight: .semibold))
                Spacer()
                Text("VM \(rec.vm.id)")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6 * s) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.red)
                Text(rec.fromNode)
                    .font(.system(size: 13 * s))
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
                Image(systemName: "server.rack")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.green)
                Text(rec.toNode)
                    .font(.system(size: 13 * s))
                    .foregroundStyle(.green)
            }

            Text(rec.reason)
                .font(.system(size: 11 * s))
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
    @Environment(\.windowScale) private var s

    private var color: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var body: some View {
        Text(priority.label)
            .font(.system(size: 10 * s, weight: .semibold))
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 3 * s)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct MigrationStatusLabel: View {
    let status: MigrationRecommendation.MigrationStatus
    @Environment(\.windowScale) private var s

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
            .font(.system(size: 10 * s))
            .foregroundStyle(color)
    }
}
