import SwiftUI
struct BMDashboardView: View {
    @EnvironmentObject var viewModel: BranchManagerViewModel
    @StateObject private var performance = GeneralManagerViewModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BrandHeader(name: viewModel.station.nombre, role: "Gerente de Sucursal — \(viewModel.station.ciudad)")
                Text("Hola, \(viewModel.station.gerenteNombre)").font(.title2.bold())
                Label(viewModel.alertasCríticas.isEmpty ? "Estado de Sucursal: Excelente" : "Estado de Sucursal: Requiere atención", systemImage: "checkmark.circle")
                    .font(.caption.bold()).foregroundStyle(.white).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(PumaStyle.green)
                HStack(spacing: 8) {
                    MetricCardView(title: "Ingresos Hoy", value: PumaStyle.money(performance.performanceReport(days: 1, stations: [viewModel.station]).summary.total))
                    MetricCardView(title: "Galones Hoy", value: viewModel.todayVolume.formatted(.number.precision(.fractionLength(0))))
                }
                HStack { MetricCardView(title: "Productos Hoy", value: PumaStyle.money(performance.performanceReport(days: 1, stations: [viewModel.station]).summary.products)); MetricCardView(title: "Servicios Hoy", value: PumaStyle.money(performance.performanceReport(days: 1, stations: [viewModel.station]).summary.services)) }
                NavigationLink("Ventas de empleados y cortes por turno") { RegisterManagementView() }.buttonStyle(.borderedProminent)
                VStack(alignment: .leading) {
                    Text("Inventario de Tanques").font(.subheadline.bold())
                    HStack {
                        ForEach(viewModel.tanks) { tank in
                            TankGaugeView(title: tank.fuelType.rawValue, percentage: tank.percentage, status: tank.status, subtitle: "")
                                .background(PumaStyle.background).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.pumaCard()
                Text("Alertas Activas").font(.subheadline.bold())
                ForEach(viewModel.alertasCríticas) { tank in
                    CriticalAlertBanner(text: "\(tank.fuelType.rawValue) por debajo del mínimo. Se requiere reabastecimiento urgente.")
                }
                if viewModel.alertasCríticas.isEmpty { Text("Sin alertas críticas hoy").font(.caption).foregroundStyle(PumaStyle.green) }
                Text("Acciones Rápidas").font(.subheadline.bold())
                HStack {
                    NavigationLink { DailyCutsView() } label: { Label("Capturar Corte", systemImage: "bolt").font(.caption).pumaCard() }
                    NavigationLink { InventoryView() } label: { Label("Ver Inventario", systemImage: "drop").font(.caption).pumaCard() }
                }.buttonStyle(.plain)
                Text("Control por combustible").font(.subheadline.bold())
                PumpGrid(cut: viewModel.todayCuts.last ?? viewModel.nuevoCorte(shift: .matutino))
            }.padding(16)
        }.pumaPage().toolbar(.hidden, for: .navigationBar)
    }
}
struct CutRowView: View {
    let cut: DailyCut
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(cut.shift.rawValue).font(.subheadline.bold())
                Text("\(cut.pumps.filter { $0.completado }.count)/\(cut.pumps.count) registros completos").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(cut.cerrado ? "Cerrado" : "Pendiente").font(.caption.bold()).foregroundStyle(cut.cerrado ? PumaStyle.green : .orange)
        }.pumaCard()
    }
}
struct DailyCutsView: View {
    @EnvironmentObject var viewModel: BranchManagerViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink("Ventas y cortes por turno") { RegisterManagementView() }.buttonStyle(.borderedProminent)
                Text(Date().formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                ForEach(viewModel.cutsOrdenados) { cut in
                    NavigationLink { CutFormView(corte: cut) } label: {
                        VStack(alignment: .leading) { Text(cut.fecha.formatted(date: .abbreviated, time: .omitted)).font(.caption); CutRowView(cut: cut) }
                    }.buttonStyle(.plain)
                }
                Text("Los nuevos cortes se realizan desde Ventas y cortes por turno. Las capturas anteriores se conservan como historial.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.navigationTitle("Cortes del Día").pumaPage()
    }
}
struct PumpGrid: View {
    let cut: DailyCut
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(cut.pumps.sorted { $0.pumpNumber < $1.pumpNumber }) { pump in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "fuelpump.fill").foregroundStyle(pump.completado ? PumaStyle.green : .gray)
                    Text(cut.registerSource == true ? "Control \(pump.pumpNumber)" : "Registro \(pump.pumpNumber)").font(.caption.bold())
                    Text(pump.fuelType.rawValue).font(.caption2)
                    Text(pump.completado ? "Registrada" : "Pendiente").font(.caption2).foregroundStyle(pump.completado ? PumaStyle.green : .secondary)
                    Text("\(pump.ventasGalones, specifier: "%.1f") gal").font(.caption2)
                }.pumaCard()
            }
        }
    }
}
struct PumpsView: View {
    @EnvironmentObject var viewModel: BranchManagerViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tres controles: Súper, Regular y Diésel").font(.headline)
                ForEach(CutShift.allCases) { shift in
                    Text(shift.rawValue).font(.subheadline.bold())
                    PumpGrid(cut: viewModel.nuevoCorte(shift: shift))
                    NavigationLink("Ventas y corte del turno") { RegisterManagementView() }
                }
            }.padding(16)
        }.navigationTitle("Control de combustible").pumaPage()
    }
}
struct InventoryView: View {
    @EnvironmentObject var viewModel: BranchManagerViewModel
    @State private var showRequest = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Actualizado con cortes cerrados y llenados").font(.caption).foregroundStyle(.secondary)
                ForEach(viewModel.tanks) { tank in
                    HStack(spacing: 12) {
                        TankGaugeView(title: "", percentage: tank.percentage, status: tank.status, subtitle: "").frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tank.fuelType.rawValue).font(.headline)
                            Text("\(tank.currentGallons, specifier: "%.0f") / \(tank.capacityGallons, specifier: "%.0f") gal").font(.subheadline)
                            Text(tank.status.rawValue).font(.caption).foregroundStyle(tank.status.color)
                        }
                        Spacer()
                        Text("\(Int(tank.percentage * 100))%").font(.caption.bold()).foregroundStyle(tank.status.color)
                    }.pumaCard()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Historial de Recepciones").font(.subheadline.bold())
                    ForEach(viewModel.station.receipts.reversed()) { receipt in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(receipt.supplier) (\(receipt.fuel.rawValue))").font(.caption.bold())
                                Text(receipt.date).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(receipt.volume, specifier: "%.0f") gal ✓").font(.caption).foregroundStyle(PumaStyle.green)
                        }
                    }
                    ForEach(viewModel.cutsOrdenados.filter { $0.cerrado }) { cut in
                        ForEach(cut.purchases) { purchase in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(purchase.proveedor) (\(purchase.fuelType.rawValue))").font(.caption.bold())
                                    Text(cut.fecha.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(purchase.galones, specifier: "%.0f") gal ✓").font(.caption).foregroundStyle(PumaStyle.green)
                            }
                        }
                    }
                }.pumaCard()
            }.padding(16)
        }.navigationTitle("Inventario de Combustible").navigationBarTitleDisplayMode(.inline).pumaPage()
            .safeAreaInset(edge: .bottom) {
                Button { showRequest = true } label: { Label("Solicitar Reabastecimiento", systemImage: "truck.box").frame(maxWidth: .infinity).padding(12) }
                    .buttonStyle(.borderedProminent).padding(16).background(PumaStyle.background)
            }
            .sheet(isPresented: $showRequest) {
                NavigationStack { ReplenishmentView(station: viewModel.station) }
            }
    }
}
struct ReplenishmentView: View {
    let station: Station
    @Environment(\.dismiss) var dismiss
    @State private var fuel: FuelType = .diésel
    @State private var amount = 1000.0
    var body: some View {
        Form {
            Picker("Combustible", selection: $fuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
            TextField("Galones solicitados", value: $amount, format: .number).keyboardType(.decimalPad)
            if amount.isFinite && amount > 0 {
                ShareLink(item: "Solicitud de reabastecimiento: \(station.nombre), \(fuel.rawValue), \(amount.formatted()) galones.") {
                    Label("Compartir solicitud", systemImage: "square.and.arrow.up")
                }
            }
        }.navigationTitle("Reabastecimiento").toolbar { Button("Listo") { dismiss() } }
    }
}
