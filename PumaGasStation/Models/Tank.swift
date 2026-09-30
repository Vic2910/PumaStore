//
//  Tank.swift
//  PumaGasStation
//

import Foundation

enum TankStatus: String, Equatable {
    case óptimo = "Óptimo"
    case medio = "Medio"
    case crítico = "Crítico"


}

struct Tank: Identifiable, Codable {
    let id: UUID
    var fuelType: FuelType
    var capacityGallons: Double
    var currentGallons: Double

    init(id: UUID = UUID(), fuelType: FuelType, capacityGallons: Double, currentGallons: Double) {
        self.id = id
        self.fuelType = fuelType
        self.capacityGallons = capacityGallons
        self.currentGallons = currentGallons
    }

    var percentage: Double {
        guard capacityGallons > 0 else { return 0 }
        return max(0, min(1, currentGallons / capacityGallons))
    }

    /// Reglas de negocio para prever desabastecimiento a corto plazo.
    var status: TankStatus {
        switch percentage {
        case 0..<0.25: return .crítico
        case 0.25..<0.6: return .medio
        default: return .óptimo
        }
    }
}
