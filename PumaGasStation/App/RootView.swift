import SwiftUI
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var remote = SupabaseService.shared
    var body: some View {
        Group {
            if let user = authViewModel.currentUser {
                if user.role == .gerenteGeneral { GeneralShell() }
                else if user.role == .vendedor || user.role == .despachador { WorkerRegisterView() }
                else if let station = MockDataService.shared.station(for: user) { BranchShell(station: station).id(station.id) }
                else { NavigationStack { ProfileView() } }
            } else { LoginView() }
        }.tint(PumaStyle.green).preferredColorScheme(.light)
            .disabled(remote.busy)
            .overlay(alignment: .top) { if remote.busy { ProgressView("Conectando…").padding(10).background(.regularMaterial).clipShape(Capsule()) } }
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
            NavigationStack { OperationsMenuView() }.tabItem { Label("Más", systemImage: "line.3.horizontal") }
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
            NavigationStack { PumpsView() }.tabItem { Label("Control", systemImage: "waveform.path.ecg") }
            NavigationStack { OperationsMenuView() }.tabItem { Label("Más", systemImage: "line.3.horizontal") }
        }.environmentObject(model)
    }
}
