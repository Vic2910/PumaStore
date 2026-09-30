import XCTest
@testable import PumaGasStation

final class BusinessRulesTests: XCTestCase {
    private var store: MockDataService!
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = MockDataService(storageURL: directory.appendingPathComponent("data.json"))
        store.stations = [Station(nombre: "Prueba", direccion: "San Salvador", ciudad: "San Salvador", tanks: FuelType.allCases.map { Tank(fuelType: $0, capacityGallons: 1000, currentGallons: 500) }, gerenteNombre: "Prueba")]
    }
    override func tearDownWithError() throws {
        store = nil
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func cut(shift: CutShift = .matutino, closed: Bool = true) -> DailyCut {
        DailyCut(shift: shift, pumps: (1...6).map {
            PumpReading(pumpNumber: $0, fuelType: $0 <= 2 ? .súper : ($0 <= 4 ? .regular : .diésel), ventasGalones: 10, ventasMonto: 40, completado: true)
        }, cerrado: closed)
    }
    func testExactlySixUniquePumpsAreRequired() throws {
        var value = cut()
        value.pumps[5].pumpNumber = 1
        XCTAssertFalse(value.todasLasBombasCompletas)
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
        value = cut(); value.pumps.removeLast()
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
        value = cut(); value.pumps[5].completado = false
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
    }
    func testClosingBalancesInventoryAndCannotApplyTwice() throws {
        var value = cut()
        value.purchases = [PurchaseEntry(fuelType: .súper, galones: 100, costoTotal: 300, proveedor: "PUMA")]
        value.losses = [LossEntry(fuelType: .súper, galones: 5, motivo: "Merma")]
        let id = store.stations[0].id
        try store.saveCut(value, in: id)
        XCTAssertEqual(store.stations[0].tank(for: .súper)!.currentGallons, 575)
        XCTAssertEqual(store.stations[0].totalVentasMonto, 240)
        XCTAssertThrowsError(try store.saveCut(value, in: id))
        XCTAssertEqual(store.stations[0].tank(for: .súper)!.currentGallons, 575)
    }
    func testOnlyTwoDistinctShiftsPerDayAndDraftResumes() throws {
        let id = store.stations[0].id
        var morning = cut(closed: false)
        try store.saveCut(morning, in: id)
        XCTAssertEqual(store.stations[0].totalVentasMonto, 0)
        XCTAssertEqual(store.stations[0].tanks[0].currentGallons, 500)
        let model = BranchManagerViewModel(station: store.stations[0], dataService: store)
        XCTAssertEqual(model.nuevoCorte(shift: .matutino).id, morning.id)
        morning.cerrado = true
        try store.saveCut(morning, in: id)
        XCTAssertThrowsError(try store.saveCut(cut(), in: id))
        try store.saveCut(cut(shift: .vespertino), in: id)
        XCTAssertEqual(store.stations[0].cuts.count, 2)
    }
    func testInvalidNumbersAndStockAreRejectedAtomically() throws {
        var value = cut()
        value.pumps[0].ventasGalones = .nan
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
        value = cut(); value.pumps[0].ventasGalones = 600
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
        value = cut(); value.purchases = [PurchaseEntry(fuelType: .diésel, galones: 1000, costoTotal: 3000, proveedor: "PUMA")]
        XCTAssertThrowsError(try store.saveCut(value, in: store.stations[0].id))
        XCTAssertTrue(store.stations[0].cuts.isEmpty)
        XCTAssertEqual(store.stations[0].tanks[0].currentGallons, 500)
    }
    func testThresholdBoundariesAndWeightedGlobalLevel() {
        XCTAssertEqual(Tank(fuelType: .súper, capacityGallons: 100, currentGallons: 24.99).status, .crítico)
        XCTAssertEqual(Tank(fuelType: .súper, capacityGallons: 100, currentGallons: 25).status, .medio)
        XCTAssertEqual(Tank(fuelType: .súper, capacityGallons: 100, currentGallons: 60).status, .óptimo)
        store.stations[0].tanks = [Tank(fuelType: .súper, capacityGallons: 100, currentGallons: 100)]
        store.stations.append(Station(nombre: "Otra", direccion: "Santa Ana", ciudad: "Santa Ana", tanks: [Tank(fuelType: .súper, capacityGallons: 900, currentGallons: 0)], gerenteNombre: ""))
        let model = GeneralManagerViewModel(dataService: store)
        XCTAssertEqual(model.galones(for: .súper).actual, 100)
        XCTAssertEqual(model.galones(for: .súper).capacidad, 1000)
        XCTAssertEqual(model.status(for: .súper), .crítico)
        model.selectedStationID = store.stations[0].id
        XCTAssertEqual(model.status(for: .súper), .óptimo)
    }
    func testPersistenceAndClosedTotalsAcrossBranches() throws {
        try store.saveCut(cut(), in: store.stations[0].id)
        let restored = MockDataService(storageURL: directory.appendingPathComponent("data.json"))
        XCTAssertEqual(restored.stations[0].cuts.count, 1)
        XCTAssertEqual(restored.stations[0].tanks[0].currentGallons, 480)
        let model = GeneralManagerViewModel(dataService: restored)
        XCTAssertEqual(model.todaySales, 240)
        XCTAssertEqual(model.todayVolume, 60)
        var second = restored.stations[0]
        second = Station(nombre: "Segunda", direccion: "Santa Ana", ciudad: "Santa Ana", tanks: second.tanks, cuts: [cut()], gerenteNombre: "")
        restored.stations.append(second)
        XCTAssertEqual(model.todaySales, 480)
        model.selectedStationID = restored.stations[0].id
        XCTAssertEqual(model.todaySales, 240)
    }
}
