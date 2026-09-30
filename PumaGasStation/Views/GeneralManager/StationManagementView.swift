import SwiftUI
struct StationManagementView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @State private var showingAddStation = false
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Buscar sucursal...", text: $search); Image(systemName: "slider.horizontal.3").foregroundStyle(PumaStyle.green) }.pumaCard()
                ForEach(viewModel.stations.filter { search.isEmpty || $0.nombre.localizedCaseInsensitiveContains(search) || $0.ciudad.localizedCaseInsensitiveContains(search) }) { station in
                    NavigationLink { StationDetailView(station: station) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(station.nombre).font(.headline); Spacer(); Text("Activa").font(.caption2.bold()).foregroundStyle(PumaStyle.green).padding(4).background(PumaStyle.green.opacity(0.1)) }
                            Text(station.ciudad).font(.caption).foregroundStyle(PumaStyle.green)
                            Text(station.direccion).font(.caption2).foregroundStyle(.secondary)
                            Label("6 bombas", systemImage: "bolt").font(.caption2)
                            Divider()
                            HStack { Text("👩🏻‍🦰"); Text(station.gerenteNombre).font(.caption); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.pumaCard()
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }.navigationTitle("Sucursales").navigationBarTitleDisplayMode(.inline).pumaPage()
            .toolbar { Button { showingAddStation = true } label: { Label("Nueva", systemImage: "plus").font(.caption.bold()) }.buttonStyle(.borderedProminent) }
            .sheet(isPresented: $showingAddStation) { AddStationView() }
    }
}
struct ManagersView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @State private var showAdd = false
    @State private var selected: User?
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.managers) { user in
                    HStack(alignment: .top, spacing: 12) {
                        Text("👩🏻‍🦰").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.nombre).font(.headline)
                            Text(user.usuario).font(.caption).foregroundStyle(.secondary)
                            Text("Sucursal: \(viewModel.stations.first { $0.id == user.stationID }?.nombre ?? "Ninguna")").font(.caption).foregroundStyle(PumaStyle.green)
                            Button("Reasignar") { selected = user }.font(.caption.bold()).buttonStyle(.bordered)
                        }
                        Spacer(minLength: 0)
                        Text(user.stationID == nil ? "Disponible" : "Asignado").font(.caption2).foregroundStyle(PumaStyle.green)
                    }.pumaCard()
                }
            }.padding(16)
        }.navigationTitle("Gerentes").navigationBarTitleDisplayMode(.inline).pumaPage()
            .toolbar { Button { showAdd = true } label: { Label("Asignar", systemImage: "plus") }.buttonStyle(.borderedProminent) }
            .sheet(isPresented: $showAdd) { AddManagerView() }
            .sheet(item: $selected) { user in ManagerAssignmentView(user: user) }
    }
}
struct ManagerAssignmentView: View {
    let user: User
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var stationID: UUID?
    var body: some View {
        NavigationStack {
            Form {
                Text(user.nombre)
                Picker("Sucursal", selection: $stationID) {
                    Text("Sin asignar").tag(UUID?.none)
                    ForEach(viewModel.stations) { Text($0.nombre).tag(Optional($0.id)) }
                }
            }.navigationTitle("Reasignar Gerente")
                .onAppear { stationID = user.stationID }
                .toolbar {
                    Button("Cancelar") { dismiss() }
                    Button("Guardar") { if viewModel.assignManager(userID: user.id, stationID: stationID) { dismiss() } }
                }
                .alert("No se pudo guardar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        }
    }
}
