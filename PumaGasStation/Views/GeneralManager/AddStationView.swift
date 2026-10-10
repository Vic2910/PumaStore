//
//  AddStationView.swift
//  PumaGasStation
//

import SwiftUI

struct AddStationView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var direccion = ""
    @State private var ciudad = ""
    @State private var gerenteNombre = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos de la estación") {
                    TextField("Nombre (ej. PUMA Metrocentro)", text: $nombre)
                    TextField("Dirección", text: $direccion)
                    TextField("Ciudad", text: $ciudad)
                }
                Section {
                    Text("Se creará la estación con 3 tanques (Súper, Regular, Diésel) vacíos y exactamente 6 bombas. Asigna un gerente desde Gerentes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
            .navigationTitle("Nueva Estación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { if await SupabaseService.shared.perform({ viewModel.addStation(nombre: nombre, direccion: direccion, ciudad: ciudad, gerenteNombre: gerenteNombre.isEmpty ? "Sin asignar" : gerenteNombre) }) { dismiss() } else { viewModel.errorMessage = SupabaseService.shared.message } }
                    }
                    .disabled(nombre.isEmpty || ciudad.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddStationView()
        .environmentObject(GeneralManagerViewModel())
}
