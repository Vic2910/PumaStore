import SwiftUI
import Charts
struct GMDashboardView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        let today = viewModel.performanceReport(days: 1).summary
        let branchIncome = viewModel.filteredStations.map { station in (station: station, income: viewModel.performanceReport(days: 1, stations: [station]).summary.total) }
        let maximum = max(1, branchIncome.map(\.income).max() ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrandHeader(name: "Gasolinera Puma", role: "Gerente General")
                Text("Hola, \(authViewModel.currentUser?.nombre ?? "Gabriela Díaz")").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricCardView(title: "Ingresos Totales Hoy", value: PumaStyle.money(today.total), icon: "dollarsign")
                    MetricCardView(title: "Combustible Hoy", value: PumaStyle.money(today.fuel), icon: "drop")
                    MetricCardView(title: "Productos Hoy", value: PumaStyle.money(today.products), icon: "cart")
                    MetricCardView(title: "Servicios Hoy", value: PumaStyle.money(today.services), icon: "wrench.and.screwdriver")
                    MetricCardView(title: "Galones Vendidos", value: viewModel.todayVolume.formatted(.number.precision(.fractionLength(0))), icon: "drop")
                    MetricCardView(title: "Compras Hoy", value: PumaStyle.money(viewModel.todayPurchases), icon: "truck.box")
                    MetricCardView(title: "Pérdidas Hoy (gal)", value: viewModel.todayLosses.formatted(), icon: "exclamationmark.triangle")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Actividad comercial de hoy").font(.subheadline.bold())
                    HStack { Text("Productos vendidos"); Spacer(); Text("\(today.units) unidades").bold().foregroundStyle(PumaStyle.green) }.font(.caption)
                    HStack { Text("Servicios completados"); Spacer(); Text("\(today.completed)").bold().foregroundStyle(PumaStyle.green) }.font(.caption)
                    HStack { Text("Servicios pendientes / en proceso"); Spacer(); Text("\(today.pending)").bold() }.font(.caption)
                    HStack { NavigationLink("Punto de venta") { OperationsWorkspace(module: "Ventas") }; Spacer(); NavigationLink("Servicios") { OperationsWorkspace(module: "Servicios") } }.font(.caption)
                    Text("Solo cortes cerrados, ventas confirmadas y servicios completados. Servicios agrupados por fecha de registro.").font(.caption2).foregroundStyle(.secondary)
                }.pumaCard()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButton("Todas las Sucursales", id: nil)
                        ForEach(viewModel.stations) { filterButton($0.nombre, id: $0.id) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingresos de Sucursales Hoy").font(.subheadline.bold())
                    ForEach(branchIncome, id: \.station.id) { entry in
                        let station = entry.station
                        NavigationLink { StationDetailView(station: station) } label: {
                            VStack(spacing: 5) {
                                HStack { Text(station.nombre); Spacer(); Text(PumaStyle.money(entry.income)).foregroundStyle(PumaStyle.green) }.font(.caption.bold())
                                ProgressView(value: entry.income, total: maximum).tint(PumaStyle.green)
                            }
                        }.buttonStyle(.plain)
                    }
                }.pumaCard()
                VStack(alignment: .leading) {
                    Text("Niveles de Tanques Globales").font(.subheadline.bold())
                    HStack {
                        ForEach(FuelType.allCases) { fuel in
                            let values = viewModel.galones(for: fuel)
                            TankGaugeView(title: fuel.rawValue, percentage: values.capacidad > 0 ? values.actual / values.capacidad : 0, status: viewModel.status(for: fuel), subtitle: "\(Int(values.actual)) gal")
                        }
                    }
                }.pumaCard()
                Text("Alertas Críticas").font(.subheadline.bold())
                ForEach(viewModel.filteredStations) { station in
                    ForEach(station.alertasCríticas) { tank in
                        CriticalAlertBanner(text: "\(station.nombre): \(tank.fuelType.rawValue) al \(Int(tank.percentage * 100))%")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cortes del Día (Sucursales)").font(.subheadline.bold())
                    ForEach(viewModel.filteredStations) { station in
                        HStack {
                            Text(station.nombre).font(.caption.bold())
                            Spacer()
                            Text("\(station.cuts.filter { $0.cerrado && MockDataService.calendar.isDate($0.fecha, inSameDayAs: Date()) }.count)/2 cerrados").font(.caption).foregroundStyle(PumaStyle.green)
                        }
                    }
                }.pumaCard()
                NavigationLink("Rendimiento de Ventas") { PerformanceView() }.font(.subheadline.bold())
            }.padding(16)
        }.pumaPage().toolbar(.hidden, for: .navigationBar)
    }
    private func filterButton(_ title: String, id: UUID?) -> some View {
        Button { viewModel.selectedStationID = id } label: {
            Text(title).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                .background(viewModel.selectedStationID == id ? PumaStyle.green : .white)
                .foregroundStyle(viewModel.selectedStationID == id ? .white : .primary).clipShape(Capsule())
        }
    }
}
struct PerformanceView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @State private var period = 30
    @State private var category = GeneralManagerViewModel.ReportCategory.all
    private var exportContent: String { viewModel.csvReport(days: period, category: category) }
    var body: some View {
        let report = viewModel.performanceReport(days: period)
        let summary = report.summary
        let previous = viewModel.previousReport(days: period).summary.revenue(category)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Sucursal", selection: $viewModel.selectedStationID) {
                    Text("Todas las sucursales").tag(UUID?.none)
                    ForEach(viewModel.stations) { Text($0.nombre).tag(Optional($0.id)) }
                }
                Picker("Período", selection: $period) {
                    Text("Semana").tag(7); Text("Mes").tag(30); Text("Trimestre").tag(90); Text("Año").tag(365)
                }.pickerStyle(.segmented)
                Picker("Actividad", selection: $category) { ForEach(GeneralManagerViewModel.ReportCategory.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tendencia de Ingresos").font(.subheadline.bold())
                    Text(category.rawValue).font(.caption).foregroundStyle(.secondary)
                    Chart(report.points) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value("Ingresos USD", point.revenue(category)))
                            .foregroundStyle(PumaStyle.green).symbol(.circle)
                    }.frame(height: 170)
                }.pumaCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingresos totales del período").font(.subheadline.bold())
                    Text(PumaStyle.money(summary.total)).font(.title2.bold()).foregroundStyle(PumaStyle.green)
                    reportRow("Combustible", value: PumaStyle.money(summary.fuel))
                    reportRow("Productos", value: PumaStyle.money(summary.products))
                    reportRow("Servicios completados", value: PumaStyle.money(summary.services))
                }.pumaCard()
                MetricCardView(title: "Ingresos · \(category.rawValue)", value: PumaStyle.money(summary.revenue(category)))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frente al período anterior").font(.subheadline.bold())
                    Text(previous > 0 ? String(format: "%+.1f%%", (summary.revenue(category) - previous) / previous * 100) : "Sin base de comparación").font(.headline)
                    Text("\(PumaStyle.money(previous)) · \(period) días anteriores").font(.caption).foregroundStyle(.secondary)
                }.pumaCard()
                if category == .all || category == .fuel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rendimiento por Combustible").font(.subheadline.bold())
                    ForEach(FuelType.allCases) { fuel in
                        reportRow(fuel.rawValue, value: PumaStyle.money(report.fuelSales[fuel] ?? 0))
                    }
                    reportRow("Galones vendidos", value: summary.volume.formatted())
                    reportRow("Pérdidas (gal)", value: summary.losses.formatted())
                }.pumaCard()
                }
                if category == .all || category == .products {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Productos más vendidos").font(.subheadline.bold())
                        Text("\(summary.units) unidades vendidas").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(report.products.prefix(5))) { item in reportRow("\(item.name) · \(item.count) unidades", value: PumaStyle.money(item.revenue)) }
                        if report.products.isEmpty { Text("Sin ventas en este período.").font(.caption).foregroundStyle(.secondary) }
                    }.pumaCard()
                }
                if category == .all || category == .services {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rendimiento de servicios").font(.subheadline.bold())
                        reportRow("Completados", value: String(summary.completed))
                        reportRow("Pendientes / en proceso", value: String(summary.pending))
                        reportRow("Cancelados", value: String(summary.cancelled))
                        ForEach(Array(report.services.prefix(5))) { item in reportRow("\(item.name) · \(item.count) completados", value: PumaStyle.money(item.revenue)) }
                    }.pumaCard()
                }
                Text("Ingresos, no utilidad. Solo cortes cerrados, ventas confirmadas y servicios completados. Los servicios se agrupan por fecha de registro.").font(.caption2).foregroundStyle(.secondary)
                if let url = viewModel.reportURL {
                    ShareLink(item: url) {
                        Label("Exportar Reporte del Período", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }.padding(16)
        }.navigationTitle("Análisis de Rendimiento").navigationBarTitleDisplayMode(.inline).pumaPage()
            .task(id: exportContent) { viewModel.prepareCSV(days: period, category: category) }
            .alert("No se pudo exportar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
    }
    private func reportRow(_ label: String, value: String) -> some View { HStack { Text(label); Spacer(); Text(value).bold().foregroundStyle(PumaStyle.green) }.font(.caption) }
}
