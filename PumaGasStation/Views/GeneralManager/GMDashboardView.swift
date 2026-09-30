import SwiftUI
import Charts
struct GMDashboardView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrandHeader(name: "Gasolinera Puma", role: "Gerente General")
                Text("Hola, \(authViewModel.currentUser?.nombre ?? "Gabriela Díaz")").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricCardView(title: "Ventas Totales Hoy", value: PumaStyle.money(viewModel.todaySales), icon: "dollarsign")
                    MetricCardView(title: "Galones Vendidos", value: viewModel.todayVolume.formatted(.number.precision(.fractionLength(0))), icon: "drop")
                    MetricCardView(title: "Compras Hoy", value: PumaStyle.money(viewModel.todayPurchases), icon: "truck.box")
                    MetricCardView(title: "Pérdidas Hoy (gal)", value: viewModel.todayLosses.formatted(), icon: "exclamationmark.triangle")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButton("Todas las Sucursales", id: nil)
                        ForEach(viewModel.stations) { filterButton($0.nombre, id: $0.id) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Desempeño de Sucursales").font(.subheadline.bold())
                    ForEach(viewModel.filteredStations) { station in
                        NavigationLink { StationDetailView(station: station) } label: {
                            VStack(spacing: 5) {
                                HStack { Text(station.nombre); Spacer(); Text(PumaStyle.money(station.totalVentasMonto)).foregroundStyle(PumaStyle.green) }.font(.caption.bold())
                                ProgressView(value: station.totalVentasMonto, total: max(1, viewModel.stations.map(\.totalVentasMonto).max() ?? 1)).tint(PumaStyle.green)
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Período", selection: $period) {
                    Text("Semana").tag(7); Text("Mes").tag(30); Text("Trimestre").tag(90); Text("Año").tag(365)
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tendencia de Ingresos").font(.subheadline.bold())
                    Chart(viewModel.reportPoints(days: period)) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value("Ventas USD", point.sales))
                            .foregroundStyle(PumaStyle.green).symbol(.circle)
                    }.frame(height: 170)
                }.pumaCard()
                MetricCardView(title: "Ventas del período", value: PumaStyle.money(viewModel.reportPoints(days: period).reduce(0) { $0 + $1.sales }))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rendimiento por Combustible").font(.subheadline.bold())
                    ForEach(FuelType.allCases) { fuel in
                        HStack { Text(fuel.rawValue); Spacer(); Text(PumaStyle.money(viewModel.reportSales(fuel: fuel, days: period))).bold() }.font(.subheadline)
                    }
                }.pumaCard()
                if let url = viewModel.reportURL {
                    ShareLink(item: url) {
                        Label("Exportar Reporte del Período", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }.padding(16)
        }.navigationTitle("Análisis de Rendimiento").navigationBarTitleDisplayMode(.inline).pumaPage()
            .task(id: period) { viewModel.prepareCSV(days: period) }
            .onChange(of: viewModel.todaySales) { _, _ in viewModel.prepareCSV(days: period) }
            .alert("No se pudo exportar", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Aceptar") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
    }
}
