import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ClusterViewModel
    @State private var showSecret = false

    // Local state to avoid direct @Published binding loops on macOS
    @State private var localHost = ""
    @State private var localPort = "8006"
    @State private var localTokenID = ""
    @State private var localTokenSecret = ""
    @State private var localVerifyCert = false
    @State private var localAutoRefresh: AutoRefreshInterval = .off
    @State private var isDirty = false

    var canConnect: Bool {
        !localHost.isEmpty && !localTokenID.isEmpty && !localTokenSecret.isEmpty
    }

    var body: some View {
        Form {
            connectionSection
            autoRefreshSection
            drsSection
            actionSection

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let date = viewModel.lastRefresh {
                Section {
                    Text("Zuletzt aktualisiert: \(date.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromViewModel() }
    }

    private var connectionSection: some View {
        Section("Proxmox Verbindung") {
            HStack {
                Text("Host / IP")
                    .frame(minWidth: 120, alignment: .trailing)
                TextField("192.168.1.100", text: $localHost)
                    .onChange(of: localHost) { _, _ in isDirty = true }
            }
            HStack {
                Text("Port")
                    .frame(minWidth: 120, alignment: .trailing)
                TextField("8006", text: $localPort)
                    .onChange(of: localPort) { _, _ in isDirty = true }
            }
            HStack {
                Text("API Token ID")
                    .frame(minWidth: 120, alignment: .trailing)
                TextField("root@pam!mytoken", text: $localTokenID)
                    .onChange(of: localTokenID) { _, _ in isDirty = true }
            }
            HStack {
                Text("Token Secret")
                    .frame(minWidth: 120, alignment: .trailing)
                Group {
                    if showSecret {
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $localTokenSecret)
                    } else {
                        SecureField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $localTokenSecret)
                    }
                }
                .onChange(of: localTokenSecret) { _, _ in isDirty = true }
                Button {
                    showSecret.toggle()
                } label: {
                    Image(systemName: showSecret ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
            }
            Toggle("SSL-Zertifikat prüfen", isOn: $localVerifyCert)
                .onChange(of: localVerifyCert) { _, _ in isDirty = true }
            Text("API Token: Proxmox → Datacenter → API Tokens → Add")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private var autoRefreshSection: some View {
        Section("Automatische Aktualisierung") {
            Picker("Intervall", selection: $localAutoRefresh) {
                ForEach(AutoRefreshInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .onChange(of: localAutoRefresh) { _, _ in isDirty = true }
            .pickerStyle(.segmented)
            
            if localAutoRefresh != .off {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Daten werden automatisch alle \(localAutoRefresh.rawValue) Sekunden aktualisiert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var drsSection: some View {
        Section("DRS Parameter") {
            Grid(alignment: .leading, horizontalSpacing: 24) {
                GridRow {
                    Text("Überlast-Schwellwert").foregroundStyle(.secondary)
                    Text("70%")
                }
                GridRow {
                    Text("Unterlast-Schwellwert").foregroundStyle(.secondary)
                    Text("40%")
                }
                GridRow {
                    Text("Gewichtung CPU / RAM").foregroundStyle(.secondary)
                    Text("50% / 50%")
                }
                GridRow {
                    Text("Ungleichgewicht-Trigger").foregroundStyle(.secondary)
                    Text("15%")
                }
            }
            .font(.callout)
        }
    }

    private var actionSection: some View {
        Section {
            HStack(spacing: 12) {
                if isDirty {
                    Button("Speichern") {
                        applySettings()
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    applySettings()
                    Task { await viewModel.refresh() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(viewModel.isLoading ? "Verbinde..." : "Verbindung testen & laden")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect || viewModel.isLoading)
            }
        }
    }

    private func loadFromViewModel() {
        localHost = viewModel.settings.host
        localPort = String(viewModel.settings.port)
        localTokenID = viewModel.settings.tokenID
        localTokenSecret = viewModel.settings.tokenSecret
        localVerifyCert = viewModel.settings.verifyCertificate
        localAutoRefresh = viewModel.settings.autoRefreshInterval
        isDirty = false
    }

    private func applySettings() {
        var s = ProxmoxSettings()
        s.host = localHost
        s.port = Int(localPort) ?? 8006
        s.tokenID = localTokenID
        s.tokenSecret = localTokenSecret
        s.verifyCertificate = localVerifyCert
        s.autoRefreshInterval = localAutoRefresh
        viewModel.settings = s
        isDirty = false
    }
}
