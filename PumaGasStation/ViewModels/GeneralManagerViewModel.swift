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
    /// nil = panorama general del país; un id = vista filtrada por sucursal.
    @Published var selectedStationID: UUID?

    init(dataService: MockDataService = .shared) {
        self.dataService = dataService
        dataService.$users.map { $0.filter { $0.role == .gerenteSucursal } }.assign(to: &$managers)
        dataService.$stations
            .assign(to: &$stations)
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
    var todayPurchases: Double { todayCuts.reduce(0) { $0 + $1.totalComprasMonto } }
    var todayLosses: Double { todayCuts.reduce(0) { $0 + $1.totalPerdidasGalones } }
    var todayVolume: Double { todayCuts.reduce(0) { $0 + $1.totalVentasGalones } }

    // MARK: - Gestión administrativa

    struct ReportPoint: Identifiable {
        var date: Date
        var sales: Double
        var id: Date { date }
    }
    private func reportCuts(days: Int) -> [DailyCut] {
        let start = MockDataService.calendar.date(byAdding: .day, value: -(days - 1), to: MockDataService.calendar.startOfDay(for: Date()))!
        return filteredStations.flatMap(\.cuts).filter { $0.cerrado && $0.fecha >= start && $0.fecha <= Date() }
    }
    func reportPoints(days: Int) -> [ReportPoint] {
        let grouped = Dictionary(grouping: reportCuts(days: days)) { MockDataService.calendar.startOfDay(for: $0.fecha) }
        return (0..<days).reversed().map { offset in
            let day = MockDataService.calendar.date(byAdding: .day, value: -offset, to: MockDataService.calendar.startOfDay(for: Date()))!
            return ReportPoint(date: day, sales: (grouped[day] ?? []).reduce(0) { $0 + $1.totalVentasMonto })
        }
    }
    func reportSales(fuel: FuelType, days: Int) -> Double { reportCuts(days: days).reduce(0) { $0 + $1.ventas(for: fuel) } }
    func csvReport(days: Int) -> String {
        "Fecha,Ventas USD\n" + reportPoints(days: days).map { "\($0.date.formatted(.iso8601)),\($0.sales)" }.joined(separator: "\n")
    }
    func prepareCSV(days: Int) {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("PUMA-Reporte-\(days)-dias.csv")
            try Data(csvReport(days: days).utf8).write(to: url, options: .atomic)
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
    func assignManager(userID: UUID, stationID: UUID?) -> Bool {
        commit {
            guard let index = dataService.users.firstIndex(where: { $0.id == userID && $0.role == .gerenteSucursal }) else {
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
