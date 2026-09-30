//
//  DailyCut.swift
//  PumaGasStation
//
//  Representa uno de los 2 cortes diarios (Matutino / Vespertino) de una sucursal.
//

import Foundation

enum CutShift: String, Codable, CaseIterable, Identifiable {
    case matutino = "Corte Matutino"
    case vespertino = "Corte Vespertino/Nocturno"

    var id: String { rawValue }
}

/// Registro de pérdida o daño (merma, fuga, falla técnica, derrame).
struct LossEntry: Identifiable, Codable {
    let id: UUID
    var fuelType: FuelType
    var galones: Double
    var motivo: String

    init(id: UUID = UUID(), fuelType: FuelType, galones: Double, motivo: String) {
        self.id = id
        self.fuelType = fuelType
        self.galones = galones
        self.motivo = motivo
    }
}

/// Registro de compra / recepción de combustible.
struct PurchaseEntry: Identifiable, Codable {
    let id: UUID
    var fuelType: FuelType
    var galones: Double
    var costoTotal: Double
    var proveedor: String

    init(id: UUID = UUID(), fuelType: FuelType, galones: Double, costoTotal: Double, proveedor: String) {
        self.id = id
        self.fuelType = fuelType
        self.galones = galones
        self.costoTotal = costoTotal
        self.proveedor = proveedor
    }
}

struct DailyCut: Identifiable, Codable {
    let id: UUID
    var fecha: Date
    var shift: CutShift
    var pumps: [PumpReading]
    var purchases: [PurchaseEntry]
    var losses: [LossEntry]
    var cerrado: Bool

    init(id: UUID = UUID(), fecha: Date = Date(), shift: CutShift, pumps: [PumpReading], purchases: [PurchaseEntry] = [], losses: [LossEntry] = [], cerrado: Bool = false) {
        self.id = id
        self.fecha = fecha
        self.shift = shift
        self.pumps = pumps
        self.purchases = purchases
        self.losses = losses
        self.cerrado = cerrado
    }

    // MARK: - Totales consolidados (las 6 bombas se resumen automáticamente)

    var totalVentasGalones: Double {
        pumps.reduce(0) { $0 + $1.ventasGalones }
    }

    var totalVentasMonto: Double {
        pumps.reduce(0) { $0 + $1.ventasMonto }
    }

    var totalComprasMonto: Double {
        purchases.reduce(0) { $0 + $1.costoTotal }
    }

    var totalPerdidasGalones: Double {
        losses.reduce(0) { $0 + $1.galones }
    }

    var todasLasBombasCompletas: Bool {
        pumps.count == 6 && Set(pumps.map(\.pumpNumber)) == Set(1...6) && pumps.allSatisfy { $0.completado }
    }

    func ventas(for fuel: FuelType) -> Double {
        pumps.filter { $0.fuelType == fuel }.reduce(0) { $0 + $1.ventasMonto }
    }
}
