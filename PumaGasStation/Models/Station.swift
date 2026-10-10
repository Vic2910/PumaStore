//
//  Station.swift
//  PumaGasStation
//

import Foundation

struct Station: Identifiable, Codable {
    let id: UUID
    var nombre: String
    var direccion: String
    var ciudad: String
    var tanks: [Tank]
    var cuts: [DailyCut]
    var gerenteNombre: String
    var receiptHistory: [TankReceipt]?
    var receipts: [TankReceipt] {
        get { receiptHistory ?? [] }
        set { receiptHistory = newValue }
    }

    init(id: UUID = UUID(), nombre: String, direccion: String, ciudad: String, tanks: [Tank], cuts: [DailyCut] = [], gerenteNombre: String) {
        self.id = id
        self.nombre = nombre
        self.direccion = direccion
        self.ciudad = ciudad
        self.tanks = tanks
        self.cuts = cuts
        self.gerenteNombre = gerenteNombre
    }

    var totalVentasMonto: Double {
        cuts.filter { $0.cerrado }.reduce(0) { $0 + $1.totalVentasMonto }
    }

    var totalComprasMonto: Double {
        cuts.filter { $0.cerrado }.reduce(0) { $0 + $1.totalComprasMonto } + receipts.reduce(0) { $0 + $1.cost }
    }

    var totalPerdidasGalones: Double {
        cuts.filter { $0.cerrado }.reduce(0) { $0 + $1.totalPerdidasGalones }
    }

    var alertasCríticas: [Tank] {
        tanks.filter { $0.status == .crítico }
    }

    func tank(for fuel: FuelType) -> Tank? {
        tanks.first { $0.fuelType == fuel }
    }
}
