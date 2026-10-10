import Foundation

struct Employee: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var name: String
    var document: String
    var phone: String
    var email: String
    var position: String
    var hireDate: String
    var active = true
}
struct WorkShift: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var employeeID: UUID
    var start: String
    var end: String
    var clockIn: String?
    var clockOut: String?
    var type: String?
    var notes: String?
    var cancelled: Bool?
    var status: String {
        if cancelled == true { return "Cancelado" }
        if clockOut != nil { return "Completado" }
        if clockIn != nil { return "En curso" }
        return "Programado"
    }
    var isEditable: Bool { status == "Programado" }
}
struct CommercialProduct: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var name: String
    var sku: String
    var category: String
    var price: Double
    var cost: Double
    var stock: Int
    var minimum: Int
    var active = true
}
struct SaleLine: Codable {
    var productID: UUID
    var name: String
    var sku: String
    var price: Double
    var quantity: Int
    var total: Double { (price * Double(quantity) * 100).rounded() / 100 }
}
struct CommercialSale: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var date: String
    var cashier: String
    var lines: [SaleLine]
    var payment: String
    var received: Double
    var total: Double { (lines.reduce(0) { $0 + $1.total } * 100).rounded() / 100 }
    var change: Double { received - total }
}
struct ExtraService: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var name: String
    var price: Double
    var available = true
}
struct ServiceRecord: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var serviceID: UUID
    var name: String
    var employeeID: UUID
    var date: String
    var price: Double
    var vehicle: String
    var notes: String
    var status = "Pendiente"
}
struct TankReceipt: Identifiable, Codable {
    var id = UUID()
    var stationID: UUID
    var date: String
    var fuel: FuelType
    var volume: Double
    var cost: Double
    var supplier: String
}
struct OperationsData: Codable {
    var employees: [Employee] = []
    var shifts: [WorkShift] = []
    var products: [CommercialProduct] = []
    var sales: [CommercialSale] = []
    var services: [ExtraService] = []
    var records: [ServiceRecord] = []
    var receipts: [TankReceipt] = []
    func forStation(_ id: UUID) -> OperationsData {
        OperationsData(employees: employees.filter { $0.stationID == id }, shifts: shifts.filter { $0.stationID == id }, products: products.filter { $0.stationID == id }, sales: sales.filter { $0.stationID == id }, services: services.filter { $0.stationID == id }, records: records.filter { $0.stationID == id }, receipts: receipts.filter { $0.stationID == id })
    }
    mutating func replaceStation(_ id: UUID, with data: OperationsData) {
        employees.removeAll { $0.stationID == id }; employees += data.employees
        shifts.removeAll { $0.stationID == id }; shifts += data.shifts
        products.removeAll { $0.stationID == id }; products += data.products
        sales.removeAll { $0.stationID == id }; sales += data.sales
        services.removeAll { $0.stationID == id }; services += data.services
        records.removeAll { $0.stationID == id }; records += data.records
        receipts.removeAll { $0.stationID == id }; receipts += data.receipts
    }
}
