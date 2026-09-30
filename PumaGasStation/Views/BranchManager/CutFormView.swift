//
//  CutFormView.swift
//  PumaGasStation
//
//  Formulario de captura de un corte diario: ventas (6 bombas), compras y pérdidas.
//

import SwiftUI

struct CutFormView: View {
    @EnvironmentObject var viewModel: BranchManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var formModel: CutFormViewModel
    init(corte: DailyCut) { _formModel = StateObject(wrappedValue: CutFormViewModel(corte: corte)) }
    private var corte: DailyCut { formModel.corte }
    @State private var showingAddPurchase = false
    @State private var showingAddLoss = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ForEach(CutShift.allCases) { shift in
                        Button { formModel.selectShift(shift, branch: viewModel) } label: {
                            Text(shift == .matutino ? "Corte Matutino" : "Corte Vespertino")
                            .font(.caption.bold()).padding(10).frame(maxWidth: .infinity)
                            .background(corte.shift == shift ? PumaStyle.green : .white)
                            .foregroundStyle(corte.shift == shift ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
                Text(corte.fecha.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if corte.cerrado { Label("Corte cerrado", systemImage: "lock.fill").foregroundStyle(PumaStyle.green) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sección Ventas").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    Text("Total Ventas del Turno ($)").font(.caption).foregroundStyle(.secondary)
                    Text(PumaStyle.money(corte.totalVentasMonto)).font(.headline).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(PumaStyle.background)
                    Text("Consolidado automáticamente de las seis bombas").font(.caption2).foregroundStyle(.secondary)
                }.pumaCard()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Combustible Recibido (gal)").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    ForEach(corte.purchases) { purchase in
                        HStack {
                            Text("\(purchase.fuelType.rawValue): \(purchase.galones, specifier: "%.1f") gal · \(PumaStyle.money(purchase.costoTotal))").font(.caption)
                            Spacer()
                            if !corte.cerrado { Button { formModel.corte.purchases.removeAll { $0.id == purchase.id } } label: { Image(systemName: "trash") }.accessibilityLabel("Eliminar compra") }
                        }
                    }
                    if !corte.cerrado { Button("Agregar compra / recepción") { showingAddPurchase = true }.font(.caption.bold()) }
                }.pumaCard()
                Text("Registro por Bomba (6)").font(.subheadline.bold())
                ForEach($formModel.corte.pumps) { $pump in
                    PumpEntryRow(pump: $pump, disabled: corte.cerrado) { value in
                        formModel.updateVolume(pumpID: pump.id, volume: value)
                    }.pumaCard()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pérdidas o Daños").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    ForEach(corte.losses) { loss in
                        HStack {
                            Text("\(loss.fuelType.rawValue): \(loss.galones, specifier: "%.1f") gal — \(loss.motivo)").font(.caption)
                            Spacer()
                            if !corte.cerrado { Button { formModel.corte.losses.removeAll { $0.id == loss.id } } label: { Image(systemName: "trash") }.accessibilityLabel("Eliminar pérdida") }
                        }
                    }
                    if !corte.cerrado { Button("Registrar pérdida / daño") { showingAddLoss = true }.font(.caption.bold()) }
                }.pumaCard()
                if !corte.cerrado {
                    Text("\(corte.pumps.filter { $0.completado }.count)/6 bombas registradas").font(.caption).foregroundStyle(.secondary)
                    Button("Guardar borrador") { if viewModel.guardar(corte: corte, cerrar: false) { dismiss() } }
                }
            }.padding(16)
        }
        .pumaPage()
        .navigationTitle("Corte Diario").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !corte.cerrado {
                Button { if viewModel.guardar(corte: corte, cerrar: true) { dismiss() } } label: {
                    Text("Consolidar y Cerrar Corte").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                }.buttonStyle(.borderedProminent).disabled(!corte.todasLasBombasCompletas).padding(16).background(PumaStyle.background)
            }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        .sheet(isPresented: $showingAddPurchase) { AddPurchaseView { formModel.corte.purchases.append($0) } }
        .sheet(isPresented: $showingAddLoss) { AddLossView { formModel.corte.losses.append($0) } }
    }
}

struct PumpEntryRow: View {
    @Binding var pump: PumpReading
    let disabled: Bool
    var onVolumeChange: (Double) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: pump.fuelType.icon)
                    .foregroundStyle(pump.fuelType.color)
                Text("Bomba \(pump.pumpNumber) · \(pump.fuelType.rawValue)")
                    .font(.subheadline.bold())
                Spacer()
                if pump.completado {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack {
                Text("Galones vendidos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", value: $pump.ventasGalones, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .disabled(disabled)
                    .onChange(of: pump.ventasGalones) { newValue in
                        onVolumeChange(newValue)
                    }
            }
            HStack {
                Text("Monto ($)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Monto real USD", value: $pump.ventasMonto, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110).disabled(disabled)
                    .font(.caption.bold())
            }
            if !disabled {
                Toggle("Bomba completada", isOn: $pump.completado)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (PurchaseEntry) -> Void

    @State private var fuelType: FuelType = .diésel
    @State private var galones = ""
    @State private var costo = ""
    @State private var proveedor = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Combustible", selection: $fuelType) {
                    ForEach(FuelType.allCases) { fuel in
                        Text(fuel.rawValue).tag(fuel)
                    }
                }
                TextField("Galones recibidos", text: $galones).keyboardType(.decimalPad)
                TextField("Costo total ($)", text: $costo).keyboardType(.decimalPad)
                TextField("Proveedor", text: $proveedor)
            }
            .navigationTitle("Nueva Compra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") {
                        onAdd(PurchaseEntry(fuelType: fuelType, galones: Double(galones) ?? 0, costoTotal: Double(costo) ?? 0, proveedor: proveedor.isEmpty ? "Proveedor no especificado" : proveedor))
                        dismiss()
                    }
                    .disabled(!(Double(galones).map { $0.isFinite && $0 > 0 } ?? false) || !(Double(costo).map { $0.isFinite && $0 >= 0 } ?? false) || proveedor.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddLossView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (LossEntry) -> Void

    @State private var fuelType: FuelType = .súper
    @State private var galones = ""
    @State private var motivo = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Combustible", selection: $fuelType) {
                    ForEach(FuelType.allCases) { fuel in
                        Text(fuel.rawValue).tag(fuel)
                    }
                }
                TextField("Galones perdidos", text: $galones).keyboardType(.decimalPad)
                TextField("Motivo (merma, fuga, falla técnica, derrame)", text: $motivo)
            }
            .navigationTitle("Registrar Pérdida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") {
                        onAdd(LossEntry(fuelType: fuelType, galones: Double(galones) ?? 0, motivo: motivo.isEmpty ? "Sin especificar" : motivo))
                        dismiss()
                    }
                    .disabled(!(Double(galones).map { $0.isFinite && $0 > 0 } ?? false) || motivo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CutFormView(corte: BranchManagerViewModel(station: MockDataService.shared.stations.first!).nuevoCorte(shift: .matutino))
            .environmentObject(BranchManagerViewModel(station: MockDataService.shared.stations.first!))
    }
}
