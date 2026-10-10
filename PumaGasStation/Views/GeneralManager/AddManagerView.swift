//
//  AddManagerView.swift
//  PumaGasStation
//

import SwiftUI

struct AddManagerView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var usuario = ""
    @State private var password = ""
    @State private var selectedStationID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del gerente") {
                    TextField("Nombre completo", text: $nombre)
                    TextField("Correo electrónico", text: $usuario).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasswordInput(title: "Contraseña", text: $password)
                }
                Section("Sucursal a vincular") {
                    Picker("Sucursal", selection: $selectedStationID) {
                        Text("Selecciona una sucursal").tag(UUID?.none)
                        ForEach(viewModel.stations) { station in
                            Text(station.nombre).tag(Optional(station.id))
                        }
                    }
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
            .navigationTitle("Alta de Gerente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let stationID = selectedStationID else { return }
                        Task { if await SupabaseService.shared.createManager(name: nombre, email: usuario, password: password, stationID: stationID) { dismiss() } else { viewModel.errorMessage = SupabaseService.shared.message } }
                    }
                    .disabled(nombre.isEmpty || usuario.isEmpty || password.isEmpty || selectedStationID == nil)
                }
            }
        }
    }
}

#Preview {
    AddManagerView()
        .environmentObject(GeneralManagerViewModel())
}
