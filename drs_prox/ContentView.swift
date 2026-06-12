import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ClusterViewModel()

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = min(max(geo.size.width / 900.0, 0.85), 1.6)
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
            .environment(\.windowScale, scale)
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
