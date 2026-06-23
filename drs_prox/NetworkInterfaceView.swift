import SwiftUI

/// Displays network interface statistics with visual indicators.
/// Bonds are shown as a group with their physical slave NICs nested underneath.
struct NetworkInterfaceView: View {
    let interfaces: [NetworkInterface]
    @Environment(\.windowScale) private var s

    struct Group: Identifiable {
        let id: String
        let primary: NetworkInterface
        let members: [NetworkInterface]
    }

    private var groups: [Group] {
        let byName = Dictionary(uniqueKeysWithValues: interfaces.map { ($0.name, $0) })
        var consumed = Set<String>()
        var result: [Group] = []

        // Bonds first, with their slaves nested
        for iface in interfaces where iface.isBond {
            let members = iface.slaves.compactMap { byName[$0] }
            consumed.insert(iface.name)
            for m in members { consumed.insert(m.name) }
            result.append(Group(id: iface.name, primary: iface, members: members))
        }

        // Standalone physical NICs (not part of any bond)
        for iface in interfaces where !iface.isBond && !consumed.contains(iface.name) {
            result.append(Group(id: iface.name, primary: iface, members: []))
        }

        // Sort: roled bonds first, then standalone by name
        return result.sorted { lhs, rhs in
            if lhs.primary.isBond != rhs.primary.isBond { return lhs.primary.isBond }
            return lhs.primary.name < rhs.primary.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.secondary)
                Text("Netzwerk-Schnittstellen")
                    .font(.system(size: 10 * s, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if interfaces.isEmpty {
                Text("Keine Netzwerk-Schnittstellen verfügbar")
                    .font(.system(size: 9 * s))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(spacing: 3 * s) {
                    ForEach(groups) { group in
                        NetworkGroupRow(group: group)
                    }
                }
            }
        }
    }
}

private struct NetworkGroupRow: View {
    let group: NetworkInterfaceView.Group
    @Environment(\.windowScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            InterfaceHeader(interface: group.primary, isBond: group.primary.isBond)
            TrafficLine(interface: group.primary)

            if group.primary.isBond, !group.members.isEmpty {
                HStack(spacing: 6 * s) {
                    Text("└")
                        .font(.system(size: 9 * s, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(group.members) { slave in
                        SlaveChip(interface: slave)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 2 * s)
            }
        }
        .padding(.vertical, 3 * s)
        .padding(.horizontal, 6 * s)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5 * s))
    }
}

private struct InterfaceHeader: View {
    let interface: NetworkInterface
    let isBond: Bool
    @Environment(\.windowScale) private var s

    var body: some View {
        HStack(spacing: 5 * s) {
            Circle()
                .fill(interface.isActive ? Color.green : Color.gray)
                .frame(width: 5 * s, height: 5 * s)
            Text(interface.name)
                .font(.system(size: isBond ? 10 * s : 9 * s,
                              weight: isBond ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(.primary)

            if let role = interface.role {
                Text(role)
                    .font(.system(size: 8 * s, weight: .medium))
                    .foregroundStyle(roleColor(role))
                    .padding(.horizontal, 4 * s)
                    .padding(.vertical, 0)
                    .background(roleColor(role).opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer()

            if let speed = interface.speed {
                Text(formatSpeed(speed))
                    .font(.system(size: 8 * s))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3 * s)
                    .padding(.vertical, 1 * s)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3 * s))
            }
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "NFS": return .blue
        case "VM-Daten": return .purple
        case "Management": return .orange
        case "Cluster-Link": return .teal
        default: return .secondary
        }
    }

    private func formatSpeed(_ mbitPerSec: Int64) -> String {
        if mbitPerSec >= 1000 {
            return "\(mbitPerSec / 1000) Gbit/s"
        } else {
            return "\(mbitPerSec) Mbit/s"
        }
    }
}

private struct SlaveChip: View {
    let interface: NetworkInterface
    @Environment(\.windowScale) private var s

    var body: some View {
        HStack(spacing: 3 * s) {
            Circle()
                .fill(interface.isActive ? Color.green : Color.gray)
                .frame(width: 4 * s, height: 4 * s)
            Text(interface.name)
                .font(.system(size: 9 * s, design: .monospaced))
                .foregroundStyle(.primary)
            if let speed = interface.speed {
                Text(formatSpeed(speed))
                    .font(.system(size: 8 * s))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4 * s)
        .padding(.vertical, 1 * s)
        .background(Color.gray.opacity(0.08))
        .clipShape(Capsule())
    }

    private func formatSpeed(_ mbitPerSec: Int64) -> String {
        if mbitPerSec >= 1000 {
            return "\(mbitPerSec / 1000)G"
        } else {
            return "\(mbitPerSec)M"
        }
    }
}

private struct TrafficLine: View {
    let interface: NetworkInterface
    @Environment(\.windowScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            TrafficIndicator(direction: "RX", bytesPerSec: interface.rxBytes, color: .blue)
            TrafficIndicator(direction: "TX", bytesPerSec: interface.txBytes, color: .purple)
            if interface.speed != nil {
                Text(String(format: "%.0f%%", interface.utilizationPercent * 100))
                    .font(.system(size: 8 * s))
                    .monospacedDigit()
                    .foregroundStyle(interface.utilizationColor)
            }
        }
    }
}

private struct TrafficIndicator: View {
    let direction: String
    let bytesPerSec: Int64
    let color: Color
    @Environment(\.windowScale) private var s

    var body: some View {
        HStack(spacing: 3 * s) {
            Image(systemName: direction == "RX" ? "arrow.down" : "arrow.up")
                .font(.system(size: 7 * s))
                .foregroundStyle(color)
            Text(ProxmoxNode.formatBytesPerSecond(bytesPerSec))
                .font(.system(size: 9 * s, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

// Preview support
#Preview {
    NetworkInterfaceView(interfaces: [
        NetworkInterface(id: "bond0", name: "bond0",
                         rxBytes: 9_700_000, txBytes: 700_000, speed: 50_000, isActive: true,
                         kind: .bond, slaves: ["nic2", "nic4"], bondMaster: nil),
        NetworkInterface(id: "bond1", name: "bond1",
                         rxBytes: 2_100_000, txBytes: 350_000, speed: 50_000, isActive: true,
                         kind: .bond, slaves: ["nic3", "nic5"], bondMaster: nil),
        NetworkInterface(id: "nic0", name: "nic0",
                         rxBytes: 50_000, txBytes: 40_000, speed: 1000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: nil),
        NetworkInterface(id: "nic1", name: "nic1",
                         rxBytes: 120_000, txBytes: 90_000, speed: 1000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: nil),
        NetworkInterface(id: "nic2", name: "nic2",
                         rxBytes: 0, txBytes: 0, speed: 25_000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: "bond0"),
        NetworkInterface(id: "nic3", name: "nic3",
                         rxBytes: 0, txBytes: 0, speed: 25_000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: "bond1"),
        NetworkInterface(id: "nic4", name: "nic4",
                         rxBytes: 0, txBytes: 0, speed: 25_000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: "bond0"),
        NetworkInterface(id: "nic5", name: "nic5",
                         rxBytes: 0, txBytes: 0, speed: 25_000, isActive: true,
                         kind: .physical, slaves: [], bondMaster: "bond1"),
    ])
    .padding()
    .frame(width: 400)
}
