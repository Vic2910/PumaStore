//
//  Pump.swift
//  PumaGasStation
//
//  Cada sucursal dispone exactamente de 6 bombas de combustible.
//

import Foundation

struct PumpReading: Identifiable, Codable {
    let id: UUID
    var pumpNumber: Int
    var fuelType: FuelType
    var ventasGalones: Double
    var ventasMonto: Double
    var completado: Bool

    init(id: UUID = UUID(), pumpNumber: Int, fuelType: FuelType, ventasGalones: Double = 0, ventasMonto: Double = 0, completado: Bool = false) {
        self.id = id
        self.pumpNumber = pumpNumber
        self.fuelType = fuelType
        self.ventasGalones = ventasGalones
        self.ventasMonto = ventasMonto
        self.completado = completado
    }
}
