//
//  GeneralManagerViewModel.swift
//  PumaGasStation
//
//  Vista consolidada y estratégica para el Gerente General.
//

import Foundation
import Combine

final class GeneralManagerViewModel: ObservableObject {
    private let dataService: MockDataService
    private var cancellables = Set<AnyCancellable>()

    @Published var errorMessage: String?
    @Published var reportURL: URL?
    @Published var managers: [User] = []
    @Published var stations: [Station] = []
    @Published private(set) var operations = OperationsData()
    /// nil = panorama general del país; un id = vista filtrada por sucursal.
    @Published var selectedStationID: UUID?

    init(dataService: MockDataService = .shared, operationsStore: OperationsStore = .shared) {
        self.dataService = dataService
        dataService.$users.map { $0.filter { $0.role == .gerenteSucursal } }.assign(to: &$managers)
        dataService.$stations
            .assign(to: &$stations)
        operationsStore.$data.assign(to: &$operations)
    }

    var filteredStations: [Station] {
        guard let selectedStationID else { return stations }
        return stations.filter { $0.id == selectedStationID }
    }

    var totalVentas: Double {
        filteredStations.reduce(0) { $0 + $1.totalVentasMonto }
    }

    var totalCompras: Double {
        filteredStations.reduce(0) { $0 + $1.totalComprasMonto }
    }

    var totalPerdidasGalones: Double {
        filteredStations.reduce(0) { $0 + $1.totalPerdidasGalones }
    }

    /// Suma de galones actuales por tipo de combustible, agregando todas las sucursales filtradas.
    func galones(for fuel: FuelType) -> (actual: Double, capacidad: Double) {
        var actual: Double = 0
        var capacidad: Double = 0
        for station in filteredStations {
            if let tank = station.tank(for: fuel) {
                actual += tank.currentGallons
                capacidad += tank.capacityGallons
            }
        }
        return (actual, capacidad)
    }

    func status(for fuel: FuelType) -> TankStatus {
        let (actual, capacidad) = galones(for: fuel)
        return Tank(fuelType: fuel, capacityGallons: capacidad, currentGallons: actual).status
    }

    var alertasCríticas: [(station: Station, tank: Tank)] {
        filteredStations.flatMap { station in
            station.alertasCríticas.map { (station, $0) }
        }
    }

    var todayCuts: [DailyCut] {
        filteredStations.flatMap(\.cuts).filter { $0.cerrado && MockDataService.calendar.isDate($0.fecha, inSameDayAs: Date()) }
    }
    var todaySales: Double { todayCuts.reduce(0) { $0 + $1.totalVentasMonto } }
    var todayPurchases: Double {
        todayCuts.reduce(0) { $0 + $1.totalComprasMonto } + filteredStations.flatMap(\.receipts).filter { receipt in
            guard let date = ISO8601DateFormatter().date(from: receipt.date) else { return false }
            return MockDataService.calendar.isDate(date, inSameDayAs: Date())
        }.reduce(0) { $0 + $1.cost }
    }
    var todayLosses: Double { todayCuts.reduce(0) { $0 + $1.totalPerdidasGalones } }
    var todayVolume: Double { todayCuts.reduce(0) { $0 + $1.totalVentasGalones } }

    // MARK: - Gestión administrativa

    enum ReportCategory: String, CaseIterable, Identifiable {
        case all = "Todas", fuel = "Combustible", products = "Productos", services = "Servicios"
        var id: String { rawValue }
    }
    struct ReportPoint: Identifiable {
        var date: Date
        var fuel = 0.0
        var products = 0.0
        var services = 0.0
        var volume = 0.0
        var losses = 0.0
        var units = 0
        var completed = 0
        var pending = 0
        var cancelled = 0
        var total: Double { Self.round(fuel + products + services) }
        static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        func revenue(_ category: ReportCategory) -> Double {
            switch category { case .all: total; case .fuel: fuel; case .products: products; case .services: services }
        }
        var id: Date { date }
    }
    struct ReportItem: Identifiable {
        var id: UUID
        var name: String
        var count = 0
        var revenue = 0.0
    }
    struct PerformanceReport {
        var points: [ReportPoint]
        var summary: ReportPoint
        var fuelSales: [FuelType: Double]
        var products: [ReportItem]
        var services: [ReportItem]
    }
    func performanceReport(days: Int, ending: Date = Date(), stations reportStations: [Station]? = nil) -> PerformanceReport {
        let calendar = MockDataService.calendar, end = calendar.startOfDay(for: ending)
        let dates = (0..<max(1, min(days, 365))).reversed().map { calendar.date(byAdding: .day, value: -$0, to: end)! }
        var points = Dictionary(uniqueKeysWithValues: dates.map { ($0, ReportPoint(date: $0)) })
        let branches = reportStations ?? filteredStations
        let ids = Set(branches.map(\.id))
        var fuelSales: [FuelType: Double] = [:], productItems: [UUID: ReportItem] = [:], serviceItems: [UUID: ReportItem] = [:]
        func day(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text).map { calendar.startOfDay(for: $0) } }
        for cut in branches.flatMap(\.cuts) where cut.cerrado {
            let date = calendar.startOfDay(for: cut.fecha)
            guard points[date] != nil else { continue }
            points[date]!.fuel += cut.totalVentasMonto; points[date]!.volume += cut.totalVentasGalones; points[date]!.losses += cut.totalPerdidasGalones
            for fuel in FuelType.allCases { fuelSales[fuel, default: 0] += cut.ventas(for: fuel) }
        }
        for sale in operations.sales where ids.contains(sale.stationID) {
            guard let date = day(sale.date), points[date] != nil else { continue }
            points[date]!.products += sale.total
            for line in sale.lines {
                points[date]!.units += line.quantity
                var item = productItems[line.productID] ?? ReportItem(id: line.productID, name: line.name)
                item.count += line.quantity; item.revenue += line.total; productItems[line.productID] = item
            }
        }
        for record in operations.records where ids.contains(record.stationID) {
            guard let date = day(record.date), points[date] != nil else { continue }
            if record.status == "Completado" {
                points[date]!.services += record.price; points[date]!.completed += 1
                var item = serviceItems[record.serviceID] ?? ReportItem(id: record.serviceID, name: record.name)
                item.count += 1; item.revenue += record.price; serviceItems[record.serviceID] = item
            } else if ["Pendiente", "En proceso"].contains(record.status) { points[date]!.pending += 1 }
            else if record.status == "Cancelado" { points[date]!.cancelled += 1 }
        }
        let ordered = dates.map { date -> ReportPoint in
            var p = points[date]!; p.fuel = ReportPoint.round(p.fuel); p.products = ReportPoint.round(p.products); p.services = ReportPoint.round(p.services); return p
        }
        var summary = ReportPoint(date: end)
        for p in ordered { summary.fuel += p.fuel; summary.products += p.products; summary.services += p.services; summary.volume += p.volume; summary.losses += p.losses; summary.units += p.units; summary.completed += p.completed; summary.pending += p.pending; summary.cancelled += p.cancelled }
        summary.fuel = ReportPoint.round(summary.fuel); summary.products = ReportPoint.round(summary.products); summary.services = ReportPoint.round(summary.services)
        return PerformanceReport(points: ordered, summary: summary, fuelSales: fuelSales, products: productItems.values.sorted { $0.revenue > $1.revenue }, services: serviceItems.values.sorted { $0.revenue > $1.revenue })
    }
    func previousReport(days: Int) -> PerformanceReport {
        performanceReport(days: days, ending: MockDataService.calendar.date(byAdding: .day, value: -days, to: Date())!)
    }
    func csvReport(days: Int, category: ReportCategory = .all) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = MockDataService.calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        func amount(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
        return "Fecha,Combustible USD,Productos USD,Servicios completados USD,Ingresos totales USD,Ingresos actividad seleccionada USD,Galones vendidos,Perdidas gal,Unidades productos,Servicios completados,Servicios pendientes,Servicios cancelados\n" + performanceReport(days: days).points.map { p in
            [formatter.string(from: p.date), amount(p.fuel), amount(p.products), amount(p.services), amount(p.total), amount(p.revenue(category)), amount(p.volume), amount(p.losses), String(p.units), String(p.completed), String(p.pending), String(p.cancelled)].joined(separator: ",")
        }.joined(separator: "\n")
    }
    func prepareCSV(days: Int, category: ReportCategory = .all) {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("PUMA-Reporte-\(days)-dias-\(category.rawValue).csv")
            try Data(csvReport(days: days, category: category).utf8).write(to: url, options: .atomic)
            reportURL = url
        } catch { reportURL = nil; errorMessage = error.localizedDescription }
    }
    private func commit(_ mutation: () throws -> Void) -> Bool {
        let stationsBefore = dataService.stations
        let usersBefore = dataService.users
        do { try mutation(); try dataService.persist(); errorMessage = nil; return true }
        catch { dataService.stations = stationsBefore; dataService.users = usersBefore; errorMessage = error.localizedDescription; return false }
    }
    @discardableResult
    func addStation(nombre: String, direccion: String, ciudad: String, gerenteNombre: String) -> Bool {
        commit {
            guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty, !direccion.trimmingCharacters(in: .whitespaces).isEmpty, !ciudad.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw MockDataService.StoreError.invalid("Completa nombre, dirección y ciudad.")
            }
            dataService.addStation(nombre: nombre, direccion: direccion, ciudad: ciudad, gerenteNombre: "Sin asignar")
        }
    }
    @discardableResult
    func addManager(nombre: String, usuario: String, password: String, stationID: UUID) -> Bool {
        commit {
            guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty, !usuario.trimmingCharacters(in: .whitespaces).isEmpty, password.count >= 4,
                  !dataService.users.contains(where: { $0.usuario.lowercased() == usuario.lowercased() }),
                  dataService.stations.contains(where: { $0.id == stationID }) else {
                throw MockDataService.StoreError.invalid("Verifica el usuario único, nombre, contraseña de al menos 4 caracteres y sucursal.")
            }
            // A branch has one manager; replacing the assignment releases the previous manager.
            for index in dataService.users.indices where dataService.users[index].stationID == stationID { dataService.users[index].stationID = nil }
            let manager = dataService.addManager(nombre: nombre, usuario: usuario, password: password, stationID: stationID)
            guard manager.password == password else { throw MockDataService.StoreError.invalid("No se pudo guardar la credencial en el llavero del dispositivo.") }
        }
    }
    func setManagerActive(userID: UUID, active: Bool) -> Bool {
        commit {
            guard let index = dataService.users.firstIndex(where: { $0.id == userID && $0.role == .gerenteSucursal }) else { throw MockDataService.StoreError.invalid("Gerente inexistente.") }
            if !active {
                if let branch = dataService.stations.firstIndex(where: { $0.id == dataService.users[index].stationID }) { dataService.stations[branch].gerenteNombre = "Sin asignar" }
                dataService.users[index].stationID = nil
            }
            dataService.users[index].active = active
        }
    }
    func assignManager(userID: UUID, stationID: UUID?) -> Bool {
        commit {
            guard let index = dataService.users.firstIndex(where: { $0.id == userID && $0.role == .gerenteSucursal && $0.isActive }) else {
                throw MockDataService.StoreError.invalid("Gerente inexistente.")
            }
            if let stationID, !dataService.stations.contains(where: { $0.id == stationID }) { throw MockDataService.StoreError.invalid("Sucursal inexistente.") }
            let oldStation = dataService.users[index].stationID
            if let old = dataService.stations.firstIndex(where: { $0.id == oldStation }) { dataService.stations[old].gerenteNombre = "Sin asignar" }
            if let stationID {
                for other in dataService.users.indices where other != index && dataService.users[other].stationID == stationID { dataService.users[other].stationID = nil }
                if let branch = dataService.stations.firstIndex(where: { $0.id == stationID }) { dataService.stations[branch].gerenteNombre = dataService.users[index].nombre }
            }
            dataService.users[index].stationID = stationID
        }
    }
}
