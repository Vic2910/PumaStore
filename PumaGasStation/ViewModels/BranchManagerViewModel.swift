//
//  BranchManagerViewModel.swift
//  PumaGasStation
//
//  Gestión operativa del día a día de una sucursal asignada.
//

import Foundation
import Combine

final class BranchManagerViewModel: ObservableObject {
    private let dataService: MockDataService
    private var cancellables = Set<AnyCancellable>()

    @Published var errorMessage: String?
    @Published var station: Station
    @Published private var registerSales: [RegisterSale] = []

    init(station: Station, dataService: MockDataService = .shared) {
        self.dataService = dataService
        self.station = station
        OperationsStore.shared.$registerSales.assign(to: &$registerSales)
        dataService.$stations
            .sink { [weak self] stations in
                guard let self, let updated = stations.first(where: { $0.id == self.station.id }) else { return }
                self.station = updated
            }
            .store(in: &cancellables)
    }

    var tanks: [Tank] { station.tanks }

    var alertasCríticas: [Tank] { station.alertasCríticas }

    var cutsOrdenados: [DailyCut] {
        station.cuts.sorted { $0.fecha > $1.fecha }
    }

    /// Crea un nuevo corte en blanco con las 6 bombas sin completar.
    func nuevoCorte(shift: CutShift) -> DailyCut {
        if let existing = station.cuts.first(where: { $0.shift == shift && MockDataService.calendar.isDate($0.fecha, inSameDayAs: Date()) }) { return existing }
        let pumps = (1...3).map { n -> PumpReading in
            let fuel: FuelType = n == 1 ? .súper : (n == 2 ? .regular : .diésel)
            return PumpReading(pumpNumber: n, fuelType: fuel)
        }
        return DailyCut(shift: shift, pumps: pumps)
    }

    @discardableResult
    func guardar(corte: DailyCut, cerrar: Bool) -> Bool {
        var actualizado = corte
        actualizado.cerrado = cerrar
        do {
            try dataService.saveCut(actualizado, in: station.id)
            errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    var todayCuts: [DailyCut] {
        station.cuts.filter { MockDataService.calendar.isDate($0.fecha, inSameDayAs: Date()) }
    }
    var todaySales: Double { todayCuts.filter { $0.cerrado && $0.registerSource != true }.reduce(0) { $0 + $1.totalVentasMonto } + todayRegisterSales.reduce(0) { $0 + $1.fuel_total } }
    private var todayRegisterSales: [RegisterSale] { registerSales.filter { $0.station_id == station.id && $0.work_day == OperationsStore.workDay() } }
    var todayVolume: Double { todayCuts.filter { $0.cerrado && $0.registerSource != true }.reduce(0) { $0 + $1.totalVentasGalones } + todayRegisterSales.reduce(0) { $0 + $1.gallons } }
}

/// Owns the editable draft; committed business validation stays in the shared store.
final class CutFormViewModel: ObservableObject {
    @Published var corte: DailyCut
    init(corte: DailyCut) { self.corte = corte }
    func updateVolume(pumpID: UUID, volume: Double) {
        guard !corte.cerrado, let index = corte.pumps.firstIndex(where: { $0.id == pumpID }) else { return }
        corte.pumps[index].ventasMonto = volume * corte.pumps[index].fuelType.precioReferencia
    }
    @MainActor func selectShift(_ shift: CutShift, branch: BranchManagerViewModel) async {
        guard shift != corte.shift else { return }
        if !corte.cerrado, !(await SupabaseService.shared.perform { branch.guardar(corte: corte, cerrar: false) }) { return }
        corte = branch.nuevoCorte(shift: shift)
    }
}
