import XCTest
@testable import PumaGasStation

final class BusinessRulesTests: XCTestCase {
    func testPastShiftCannotBeAssignedButHistoryCanBePreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = OperationsStore(storageURL: url), station = UUID()
        let employee = Employee(stationID: station, name: "Ana", document: "PAST", phone: "555", email: "", position: "Cajera", hireDate: OperationsStore.stamp())
        XCTAssertTrue(store.saveEmployee(employee))
        let yesterday = MockDataService.calendar.date(byAdding: .day, value: -1, to: MockDataService.calendar.startOfDay(for: Date()))!
        let old = WorkShift(stationID: station, employeeID: employee.id, start: OperationsStore.stamp(yesterday), end: OperationsStore.stamp(yesterday.addingTimeInterval(8 * 3600)))
        XCTAssertFalse(store.saveShift(old))
        XCTAssertTrue(store.data.shifts.isEmpty)
        var historical = store.data; historical.shifts = [old]
        XCTAssertTrue(store.restore(historical))
        var note = old; note.notes = "Historial conservado"
        XCTAssertTrue(store.saveShift(note))
        XCTAssertTrue(store.cancelShift(old.id))
        XCTAssertEqual(store.data.shifts.count, 1)
    }
    func testPerformanceCombinesHistoricalIncomeAndFiltersLocalDays() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = MockDataService(storageURL: folder.appendingPathComponent("stations.json"))
        let operations = OperationsStore(storageURL: folder.appendingPathComponent("operations.json"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z"))
        let branch = UUID(), other = UUID(), product = UUID(), service = UUID(), employee = UUID()
        let pump = PumpReading(pumpNumber: 1, fuelType: .súper, ventasGalones: 10, ventasMonto: 100, completado: true)
        let closed = DailyCut(fecha: date, shift: .matutino, pumps: [pump], cerrado: true)
        let draft = DailyCut(fecha: date, shift: .vespertino, pumps: [pump], cerrado: false)
        local.stations = [Station(id: branch, nombre: "A", direccion: "Calle", ciudad: "Ciudad", tanks: [], cuts: [closed, draft], gerenteNombre: ""), Station(id: other, nombre: "B", direccion: "Calle", ciudad: "Ciudad", tanks: [], cuts: [closed], gerenteNombre: "")]
        var snapshot = OperationsData()
        let line = SaleLine(productID: product, name: "Aceite", sku: "OIL", price: 10, quantity: 2)
        snapshot.sales = [CommercialSale(stationID: branch, date: "2026-10-07T06:00:00Z", cashier: "Ana", lines: [line], payment: "Efectivo", received: 20), CommercialSale(stationID: branch, date: "2026-10-07T05:59:59Z", cashier: "Ana", lines: [line], payment: "Efectivo", received: 20), CommercialSale(stationID: other, date: "2026-10-08T12:00:00Z", cashier: "Ana", lines: [line], payment: "Efectivo", received: 20)]
        snapshot.records = ["Completado", "Pendiente", "En proceso", "Cancelado"].map { ServiceRecord(stationID: branch, serviceID: service, name: "Lavado", employeeID: employee, date: "2026-10-08T12:00:00Z", price: 30, vehicle: "", notes: "", status: $0) }
        XCTAssertTrue(operations.restore(snapshot))
        let model = GeneralManagerViewModel(dataService: local, operationsStore: operations)
        model.selectedStationID = branch
        let report = model.performanceReport(days: 3, ending: date)
        XCTAssertEqual(report.summary.fuel, 100)
        XCTAssertEqual(report.summary.products, 20)
        XCTAssertEqual(report.summary.services, 30)
        XCTAssertEqual(report.summary.total, 150)
        XCTAssertEqual(report.summary.revenue(.products), 20)
        XCTAssertEqual(report.summary.units, 2)
        XCTAssertEqual(report.summary.completed, 1)
        XCTAssertEqual(report.summary.pending, 2)
        XCTAssertEqual(report.summary.cancelled, 1)
        XCTAssertEqual(report.points.map(\.total), [20, 30, 100])
        model.selectedStationID = nil
        XCTAssertEqual(model.performanceReport(days: 3, ending: date).summary.total, 270)
        // A remote refresh changes the observable report without rebuilding the view model.
        snapshot.sales.removeAll()
        XCTAssertTrue(operations.restore(snapshot))
        XCTAssertEqual(model.performanceReport(days: 3, ending: date).summary.products, 0)
    }
    func testShiftCancellationRetainsHistoryAndReleasesSchedule() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let operations = OperationsStore(storageURL: url), stationID = UUID()
        let employee = Employee(stationID: stationID, name: "José", document: "DOC-1", phone: "555", email: "", position: "Despachador", hireDate: "2026-10-01T00:00:00Z")
        XCTAssertTrue(operations.saveEmployee(employee))
        var shift = WorkShift(stationID: stationID, employeeID: employee.id, start: "2026-10-13T04:00:00Z", end: "2026-10-13T12:00:00Z")
        shift.type = "Noche"
        XCTAssertTrue(operations.saveShift(shift))
        XCTAssertEqual(shift.status, "Programado")
        XCTAssertTrue(operations.cancelShift(shift.id))
        XCTAssertEqual(operations.data.shifts[0].status, "Cancelado")
        XCTAssertFalse(operations.clock(shift.id))
        var replacement = shift; replacement.id = UUID()
        XCTAssertTrue(operations.saveShift(replacement))
        XCTAssertEqual(operations.data.shifts.count, 2)
    }
    func testNewStationCapacityAndInactiveManager() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let local = MockDataService(storageURL: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(local.stations.allSatisfy { $0.tanks.allSatisfy { $0.capacityGallons == 10000 } })
        local.addStation(nombre: "Nueva", direccion: "Calle", ciudad: "Ciudad", gerenteNombre: "")
        XCTAssertTrue(local.stations.last!.tanks.allSatisfy { $0.capacityGallons == 10000 })
        let model = GeneralManagerViewModel(dataService: local)
        let manager = local.users.first { $0.role == .gerenteSucursal }!
        XCTAssertTrue(model.setManagerActive(userID: manager.id, active: false))
        XCTAssertNil(local.authenticate(usuario: manager.usuario, password: "1234"))
    }
    func testCommercialSaleIsAtomicAndKeepsPriceHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let operations = OperationsStore(storageURL: url), station = UUID()
        var product = CommercialProduct(stationID: station, name: "Aceite", sku: "LUB-1", category: "Lubricantes", price: 10, cost: 5, stock: 5, minimum: 2)
        XCTAssertTrue(operations.saveProduct(product))
        XCTAssertFalse(operations.sell(stationID: station, quantities: [product.id: 6], cashier: "Carlos", payment: "Efectivo", received: 100))
        XCTAssertEqual(operations.data.products[0].stock, 5)
        operations.error = nil
        XCTAssertTrue(operations.sell(stationID: station, quantities: [product.id: 2], cashier: "Carlos", payment: "Efectivo", received: 25))
        XCTAssertEqual(operations.data.products[0].stock, 3)
        XCTAssertEqual(operations.data.sales[0].change, 5)
        product.stock = 3; product.price = 99
        XCTAssertTrue(operations.saveProduct(product))
        XCTAssertEqual(operations.data.sales[0].total, 20)
    }
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
