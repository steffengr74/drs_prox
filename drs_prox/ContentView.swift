import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ClusterViewModel()

    var body: some View {
        TabView {
            ClusterOverviewView()
                .environmentObject(viewModel)
                .tabItem { Label("Cluster", systemImage: "server.rack") }

            RecommendationsView()
                .environmentObject(viewModel)
                .tabItem { Label("DRS", systemImage: "arrow.triangle.swap") }

            SettingsView()
                .environmentObject(viewModel)
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .task {
            if viewModel.settings.isConfigured {
                await viewModel.refresh()
            }
        }
    }
}

#Preview {
    ContentView()
}
