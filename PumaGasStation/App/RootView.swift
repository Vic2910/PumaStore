import SwiftUI
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        Group {
            if let user = authViewModel.currentUser {
                if user.role == .gerenteGeneral { GeneralShell() }
                else if let station = MockDataService.shared.station(for: user) { BranchShell(station: station).id(station.id) }
                else { NavigationStack { ProfileView() } }
            } else { LoginView() }
        }.tint(PumaStyle.green).preferredColorScheme(.light)
    }
}
struct GeneralShell: View {
    @StateObject private var model = GeneralManagerViewModel()
    var body: some View {
        TabView {
            NavigationStack { GMDashboardView() }.tabItem { Label("Dashboard", systemImage: "square.grid.3x3") }
            NavigationStack { StationManagementView() }.tabItem { Label("Sucursales", systemImage: "mappin.and.ellipse") }
            NavigationStack { ManagersView() }.tabItem { Label("Gerentes", systemImage: "person.2") }
            NavigationStack { PerformanceView() }.tabItem { Label("Reportes", systemImage: "chart.bar.xaxis") }
            NavigationStack { ProfileView() }.tabItem { Label("Más", systemImage: "line.3.horizontal") }
        }.environmentObject(model)
    }
}
struct BranchShell: View {
    @StateObject private var model: BranchManagerViewModel
    init(station: Station) { _model = StateObject(wrappedValue: BranchManagerViewModel(station: station)) }
    var body: some View {
        TabView {
            NavigationStack { BMDashboardView() }.tabItem { Label("Dashboard", systemImage: "square.grid.3x3") }
            NavigationStack { DailyCutsView() }.tabItem { Label("Cortes", systemImage: "doc.text") }
            NavigationStack { InventoryView() }.tabItem { Label("Inventario", systemImage: "drop") }
            NavigationStack { PumpsView() }.tabItem { Label("Bombas", systemImage: "waveform.path.ecg") }
            NavigationStack { ProfileView() }.tabItem { Label("Perfil", systemImage: "person") }
        }.environmentObject(model)
    }
}
