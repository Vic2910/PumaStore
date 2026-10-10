import Foundation
import Combine

final class OperationsStore: ObservableObject {
    static let shared = OperationsStore()
    @Published private(set) var data = OperationsData()
    @Published var registerSales: [RegisterSale] = []
    @Published var error: String?
    private var loadError: String?
    private let url: URL
    init(storageURL: URL? = nil) {
        url = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PumaGasStation/operations.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { data = try JSONDecoder().decode(OperationsData.self, from: Data(contentsOf: url)) }
            catch { loadError = "No se pudo abrir operaciones: \(error.localizedDescription)"; self.error = loadError }
        }
    }
    static func stamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }
    static func workDay(_ date: Date = Date()) -> String { let f = DateFormatter(); f.timeZone = MockDataService.calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    func restore(_ previous: OperationsData) -> Bool { commit { $0 = previous } }
    @discardableResult func commit(_ change: (inout OperationsData) throws -> Void) -> Bool {
        do {
            if let loadError { throw MockDataService.StoreError.invalid(loadError) }
            var next = data; try change(&next)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection])
            data = next; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func saveEmployee(_ employee: Employee) -> Bool {
        commit { next in
            guard !employee.name.trimmingCharacters(in: .whitespaces).isEmpty, !employee.document.isEmpty, !employee.phone.isEmpty, !employee.position.isEmpty,
                  !next.employees.contains(where: { $0.id != employee.id && $0.document == employee.document }) else { throw MockDataService.StoreError.invalid("Completa los datos. El documento debe ser único.") }
            if let index = next.employees.firstIndex(where: { $0.id == employee.id }) { next.employees[index] = employee } else { next.employees.append(employee) }
        }
    }
    func saveShift(_ shift: WorkShift) -> Bool {
        commit { next in
            if let existing = next.shifts.first(where: { $0.id == shift.id }), !existing.isEditable {
                throw MockDataService.StoreError.invalid("Solo puedes editar un turno Programado.")
            }
            let previous = next.shifts.first { $0.id == shift.id }
            let assignmentChanged = previous == nil || previous?.employeeID != shift.employeeID || previous?.stationID != shift.stationID || previous?.start != shift.start || previous?.end != shift.end
            if assignmentChanged, let start = ISO8601DateFormatter().date(from: shift.start), MockDataService.calendar.startOfDay(for: start) < MockDataService.calendar.startOfDay(for: Date()) {
                throw MockDataService.StoreError.invalid("No puedes asignar turnos en una fecha pasada.")
            }
            guard let employee = next.employees.first(where: { $0.id == shift.employeeID && $0.stationID == shift.stationID }), employee.active,
                  let start = ISO8601DateFormatter().date(from: shift.start), let end = ISO8601DateFormatter().date(from: shift.end), end > start,
                  !next.shifts.contains(where: { other in other.id != shift.id && other.cancelled != true && other.employeeID == shift.employeeID && (ISO8601DateFormatter().date(from: other.start) ?? .distantPast) < end && (ISO8601DateFormatter().date(from: other.end) ?? .distantPast) > start }) else { throw MockDataService.StoreError.invalid("Empleado inactivo, horario inválido o turno superpuesto.") }
            if assignmentChanged && next.shifts.contains(where: { other in other.id != shift.id && other.cancelled != true && other.employeeID == shift.employeeID && ISO8601DateFormatter().date(from: other.start).map { MockDataService.calendar.isDate($0, inSameDayAs: start) } == true }) {
                throw MockDataService.StoreError.invalid("El empleado solo puede tener un turno por día.")
            }
            if let index = next.shifts.firstIndex(where: { $0.id == shift.id }) { next.shifts[index] = shift } else { next.shifts.append(shift) }
        }
    }
    func cancelShift(_ id: UUID) -> Bool {
        commit { next in
            guard let index = next.shifts.firstIndex(where: { $0.id == id }), next.shifts[index].isEditable else { throw MockDataService.StoreError.invalid("Solo puedes cancelar un turno Programado.") }
            next.shifts[index].cancelled = true
        }
    }
    func clock(_ id: UUID) -> Bool {
        commit { next in
            guard let index = next.shifts.firstIndex(where: { $0.id == id }), next.shifts[index].clockOut == nil, next.shifts[index].cancelled != true,
                  next.employees.contains(where: { $0.id == next.shifts[index].employeeID && $0.active }) else { throw MockDataService.StoreError.invalid("Turno cerrado o empleado inactivo.") }
            if next.shifts[index].clockIn == nil { next.shifts[index].clockIn = Self.stamp() } else { next.shifts[index].clockOut = Self.stamp() }
        }
    }
    func saveProduct(_ product: CommercialProduct) -> Bool {
        commit { next in
            guard !product.name.isEmpty, !product.sku.isEmpty, product.price.isFinite, product.price >= 0, product.cost.isFinite, product.cost >= 0, product.stock >= 0, product.minimum >= 0,
                  !next.products.contains(where: { $0.stationID == product.stationID && $0.id != product.id && $0.sku.lowercased() == product.sku.lowercased() }) else { throw MockDataService.StoreError.invalid("Verifica SKU único, precio y existencias.") }
            if let index = next.products.firstIndex(where: { $0.id == product.id }) { next.products[index] = product } else { next.products.append(product) }
        }
    }
    func sell(stationID: UUID, quantities: [UUID: Int], cashier: String, payment: String, received: Double) -> Bool {
        commit { next in
            guard !quantities.isEmpty else { throw MockDataService.StoreError.invalid("Agrega productos al carrito.") }
            var lines: [SaleLine] = []
            for (id, quantity) in quantities {
                guard quantity > 0, let index = next.products.firstIndex(where: { $0.id == id && $0.stationID == stationID && $0.active }), next.products[index].stock >= quantity else { throw MockDataService.StoreError.invalid("Existencias insuficientes.") }
                let p = next.products[index]; lines.append(SaleLine(productID: id, name: p.name, sku: p.sku, price: p.price, quantity: quantity)); next.products[index].stock -= quantity
            }
            let total = (lines.reduce(0) { $0 + $1.total } * 100).rounded() / 100
            guard received.isFinite, received >= total else { throw MockDataService.StoreError.invalid("Pago insuficiente.") }
            next.sales.append(CommercialSale(stationID: stationID, date: Self.stamp(), cashier: cashier, lines: lines, payment: payment, received: received))
        }
    }
    func saveService(_ service: ExtraService) -> Bool {
        commit { next in
            guard !service.name.isEmpty, service.price.isFinite, service.price >= 0 else { throw MockDataService.StoreError.invalid("Verifica servicio y precio.") }
            if let index = next.services.firstIndex(where: { $0.id == service.id }) { next.services[index] = service } else { next.services.append(service) }
        }
    }
    func registerService(_ record: ServiceRecord) -> Bool {
        commit { next in
            guard next.services.contains(where: { $0.id == record.serviceID && $0.stationID == record.stationID && $0.available }), next.employees.contains(where: { $0.id == record.employeeID && $0.stationID == record.stationID && $0.active }) else { throw MockDataService.StoreError.invalid("Servicio no disponible o empleado inactivo.") }
            next.records.append(record)
        }
    }
    func transition(_ id: UUID, to status: String) -> Bool {
        commit { next in
            guard let index = next.records.firstIndex(where: { $0.id == id }), ["Pendiente", "En proceso"].contains(next.records[index].status), ["En proceso", "Completado", "Cancelado"].contains(status) else { throw MockDataService.StoreError.invalid("El servicio ya terminó.") }
            next.records[index].status = status
        }
    }
    func fill(stationID: UUID, fuel: FuelType, volume: Double, cost: Double, supplier: String) -> Bool {
        let repo = MockDataService.shared
        guard var station = repo.station(id: stationID), let index = station.tanks.firstIndex(where: { $0.fuelType == fuel }), volume.isFinite, volume > 0, cost.isFinite, cost >= 0, !supplier.trimmingCharacters(in: .whitespaces).isEmpty, station.tanks[index].currentGallons + volume <= station.tanks[index].capacityGallons else { error = "Verifica cantidad, proveedor y capacidad disponible."; return false }
        // Receipt history and inventory are committed in the original repository's snapshot.
        station.tanks[index].currentGallons += volume
        station.receipts.append(TankReceipt(stationID: stationID, date: Self.stamp(), fuel: fuel, volume: volume, cost: cost, supplier: supplier))
        let previous = repo.stations; repo.updateStation(station)
        do { try repo.persist(); return true } catch { repo.stations = previous; self.error = error.localizedDescription; return false }
    }
}
