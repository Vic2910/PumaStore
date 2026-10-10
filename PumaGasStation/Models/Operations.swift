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
    var operationalTurn: Int?
    var status: String {
        if cancelled == true { return "Cancelado" }
        if clockOut != nil { return "Completado" }
        if clockIn != nil { return "En curso" }
        return "Programado"
    }
    var isEditable: Bool { status == "Programado" }
}

struct RegisterSummary: Codable {
    var fuel: Double; var products: Double; var services: Double; var total: Double
    var sales: Int?; var units: Int?; var cash: Double?; var card: Double?
    var dayFuel: Double?; var dayProducts: Double?; var dayServices: Double?; var dayTotal: Double?
}
struct EmployeeSession: Identifiable, Codable {
    var id: UUID; var employee_id: UUID; var station_id: UUID; var shift_id: UUID
    var work_day: String; var turn: Int; var entered_at: String; var exited_at: String?
    var summary: RegisterSummary?
}
struct RegisterSale: Identifiable, Codable {
    var id: UUID; var session_id: UUID; var employee_id: UUID; var employee_name: String; var station_id: UUID
    var work_day: String; var turn: Int; var sold_at: String; var fuel: String?; var gallons: Double
    var fuel_total: Double; var product_total: Double; var service_total: Double; var total: Double
    var payment: String; var received: Double; var change: Double; var lines: [SaleLine]
    var service_id: UUID?
}
struct OperationalClosure: Identifiable, Codable {
    var id: UUID; var station_id: UUID; var work_day: String; var turn: Int; var snapshot: RegisterSummary
}
struct FuelPrice: Codable { var station_id: UUID; var fuel: String; var price: Double }
struct WorkerContext: Codable { var name: String; var products: [CommercialProduct]; var services: [ExtraService]; var shifts: [WorkShift]; var tanks: [Tank]? }
struct RegisterContext: Codable { var sessions: [EmployeeSession]; var sales: [RegisterSale]; var prices: [FuelPrice]; var closures: [OperationalClosure] }
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
    var employeeID: UUID?
    var sessionID: UUID?
    var workDay: String?
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
    var sessionID: UUID?
    var workDay: String?
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
