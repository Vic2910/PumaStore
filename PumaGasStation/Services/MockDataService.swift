//
//  MockDataService.swift
//  PumaGasStation
//
//  Repositorio local compartido con persistencia atómica y datos iniciales de demostración.
//  Se usa como singleton para que ambos módulos (Gerente General y Gerente
//  de Sucursal) compartan los cortes y el inventario en este dispositivo.
//

import Foundation
import Combine

final class MockDataService: ObservableObject {
    static let shared = MockDataService()

    @Published var stations: [Station] = []
    @Published var users: [User] = []

    private let customStorageURL: URL?
    @Published var storageError: String?
    init(storageURL: URL? = nil) {
        customStorageURL = storageURL
        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            do {
                let data = try Data(contentsOf: self.storageURL)
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                stations = snapshot.stations
                users = snapshot.users
            } catch {
                storageError = "No se pudo abrir el archivo de datos. No se sobrescribió: \(error.localizedDescription)"
            }
        } else {
            seedData()
            do { try persist() } catch { storageError = error.localizedDescription }
        }
    }

    // MARK: - Consultas

    func station(for user: User) -> Station? {
        guard let sid = user.stationID else { return nil }
        return stations.first { $0.id == sid }
    }

    func station(id: UUID) -> Station? {
        stations.first { $0.id == id }
    }

    func authenticate(usuario: String, password: String) -> User? {
        guard !password.isEmpty else { return nil }
        return users.first { $0.usuario.lowercased() == usuario.lowercased() && $0.password == password }
    }

    // MARK: - Mutaciones (Gerente General)

    func addStation(nombre: String, direccion: String, ciudad: String, gerenteNombre: String) {
        let newStation = Station(
            nombre: nombre,
            direccion: direccion,
            ciudad: ciudad,
            tanks: [
                Tank(fuelType: .súper, capacityGallons: 8000, currentGallons: 0),
                Tank(fuelType: .regular, capacityGallons: 8000, currentGallons: 0),
                Tank(fuelType: .diésel, capacityGallons: 8000, currentGallons: 0)
            ],
            cuts: [],
            gerenteNombre: gerenteNombre
        )
        stations.append(newStation)
    }

    @discardableResult
    func addManager(nombre: String, usuario: String, password: String, stationID: UUID) -> User {
        let newUser = User(nombre: nombre, usuario: usuario, password: password, role: .gerenteSucursal, stationID: stationID)
        users.append(newUser)
        if let idx = stations.firstIndex(where: { $0.id == stationID }) {
            stations[idx].gerenteNombre = nombre
        }
        return newUser
    }

    // MARK: - Mutaciones (Gerente de Sucursal)

    func updateStation(_ station: Station) {
        guard let idx = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[idx] = station
    }

    struct Snapshot: Codable { var stations: [Station]; var users: [User] }
    private var storageURL: URL {
        customStorageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PumaGasStation/data.json")
    }
    func persist() throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Snapshot(stations: stations, users: users))
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
    }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/El_Salvador")!
        return calendar
    }
    enum StoreError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
    // Validate and commit once: closed cuts are immutable and inventory never gets clamped silently.
    func saveCut(_ cut: DailyCut, in stationID: UUID) throws {
        guard let index = stations.firstIndex(where: { $0.id == stationID }) else {
            throw StoreError.invalid("Sucursal inexistente.")
        }
        var updated = stations[index]
        if let existing = updated.cuts.first(where: { $0.id == cut.id }), existing.cerrado {
            throw StoreError.invalid("Este corte ya está cerrado y no puede modificarse.")
        }
        guard !updated.cuts.contains(where: {
            $0.id != cut.id && $0.shift == cut.shift && Self.calendar.isDate($0.fecha, inSameDayAs: cut.fecha)
        }) else { throw StoreError.invalid("Ya existe este turno para la fecha seleccionada.") }
        guard cut.pumps.count == 6, Set(cut.pumps.map(\.pumpNumber)) == Set(1...6),
              cut.pumps.allSatisfy({ $0.fuelType == ($0.pumpNumber <= 2 ? .súper : ($0.pumpNumber <= 4 ? .regular : .diésel)) && $0.ventasGalones.isFinite && $0.ventasGalones >= 0 && $0.ventasMonto.isFinite && $0.ventasMonto >= 0 }),
              cut.purchases.allSatisfy({ $0.galones.isFinite && $0.galones > 0 && $0.costoTotal.isFinite && $0.costoTotal >= 0 && !$0.proveedor.trimmingCharacters(in: .whitespaces).isEmpty }),
              cut.losses.allSatisfy({ $0.galones.isFinite && $0.galones > 0 && !$0.motivo.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw StoreError.invalid("Verifica las seis bombas y los valores de ventas, compras y pérdidas.")
        }
        if cut.cerrado {
            guard cut.todasLasBombasCompletas else { throw StoreError.invalid("Completa las seis bombas antes de cerrar.") }
            for fuel in FuelType.allCases {
                guard let tankIndex = updated.tanks.firstIndex(where: { $0.fuelType == fuel }) else {
                    throw StoreError.invalid("Falta un tanque de combustible.")
                }
                let sold = cut.pumps.filter { $0.fuelType == fuel }.reduce(0) { $0 + $1.ventasGalones }
                let received = cut.purchases.filter { $0.fuelType == fuel }.reduce(0) { $0 + $1.galones }
                let lost = cut.losses.filter { $0.fuelType == fuel }.reduce(0) { $0 + $1.galones }
                let level = updated.tanks[tankIndex].currentGallons + received - sold - lost
                guard level >= 0, level <= updated.tanks[tankIndex].capacityGallons else {
                    throw StoreError.invalid("El movimiento de \(fuel.rawValue) excede el inventario o la capacidad del tanque.")
                }
                updated.tanks[tankIndex].currentGallons = level
            }
        }
        if let cutIndex = updated.cuts.firstIndex(where: { $0.id == cut.id }) { updated.cuts[cutIndex] = cut }
        else { updated.cuts.append(cut) }
        let previous = stations
        stations[index] = updated
        do { try persist() } catch { stations = previous; throw error }
    }

    // MARK: - Datos de ejemplo

    private func seedData() {
        let tanksSantaAna = [
            Tank(fuelType: .súper, capacityGallons: 10000, currentGallons: 7200),
            Tank(fuelType: .regular, capacityGallons: 10000, currentGallons: 4500),
            Tank(fuelType: .diésel, capacityGallons: 10000, currentGallons: 1800)
        ]
        let tanksSanSalvador = [
            Tank(fuelType: .súper, capacityGallons: 12000, currentGallons: 9000),
            Tank(fuelType: .regular, capacityGallons: 12000, currentGallons: 7800),
            Tank(fuelType: .diésel, capacityGallons: 12000, currentGallons: 6600)
        ]
        let tanksSonsonate = [
            Tank(fuelType: .súper, capacityGallons: 9000, currentGallons: 2000),
            Tank(fuelType: .regular, capacityGallons: 9000, currentGallons: 4700),
            Tank(fuelType: .diésel, capacityGallons: 9000, currentGallons: 4500)
        ]

        func samplePumps() -> [PumpReading] {
            (1...6).map { n in
                let fuel: FuelType = n <= 2 ? .súper : (n <= 4 ? .regular : .diésel)
                let galones = Double(80 + n * 17)
                return PumpReading(pumpNumber: n, fuelType: fuel, ventasGalones: galones, ventasMonto: galones * fuel.precioReferencia, completado: true)
            }
        }

        let cutsSantaAnaMañana = DailyCut(
            fecha: Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date(),
            shift: .matutino,
            pumps: samplePumps(),
            purchases: [PurchaseEntry(fuelType: .diésel, galones: 1000, costoTotal: 3950, proveedor: "RECOPE")],
            losses: [LossEntry(fuelType: .regular, galones: 5, motivo: "Derrame menor en manguera")],
            cerrado: true
        )
        let cutsSantaAnaTarde = DailyCut(
            fecha: Date(),
            shift: .vespertino,
            pumps: (1...6).map { PumpReading(pumpNumber: $0, fuelType: $0 <= 2 ? .súper : ($0 <= 4 ? .regular : .diésel)) },
            purchases: [],
            losses: [],
            cerrado: false
        )

        let estacionSantaAna = Station(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            nombre: "PUMA Santa Ana Centro",
            direccion: "Av. Independencia Sur",
            ciudad: "Santa Ana",
            tanks: tanksSantaAna,
            cuts: [cutsSantaAnaMañana, cutsSantaAnaTarde],
            gerenteNombre: "Abigail Rivera"
        )

        let estacionSanSalvador = Station(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            nombre: "PUMA San Salvador Norte",
            direccion: "Bulevar Constitución",
            ciudad: "San Salvador",
            tanks: tanksSanSalvador,
            cuts: [
                DailyCut(fecha: Date(), shift: .matutino, pumps: samplePumps(), cerrado: true)
            ],
            gerenteNombre: "Ana Rivas"
        )

        let estacionSonsonate = Station(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            nombre: "PUMA Sonsonate Km 65",
            direccion: "Carretera CA-8",
            ciudad: "Sonsonate",
            tanks: tanksSonsonate,
            cuts: [
                DailyCut(fecha: Date(), shift: .matutino, pumps: (1...6).map { PumpReading(pumpNumber: $0, fuelType: $0 <= 2 ? .súper : ($0 <= 4 ? .regular : .diésel)) }, cerrado: false)
            ],
            gerenteNombre: "José Portillo"
        )

        stations = [estacionSantaAna, estacionSanSalvador, estacionSonsonate]

        users = [
            User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, nombre: "Gabriela Díaz", usuario: "gerente.general", password: "1234", role: .gerenteGeneral),
            User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, nombre: "Abigail Rivera", usuario: "santa.ana", password: "1234", role: .gerenteSucursal, stationID: estacionSantaAna.id),
            User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, nombre: "Ana Rivas", usuario: "san.salvador", password: "1234", role: .gerenteSucursal, stationID: estacionSanSalvador.id),
            User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, nombre: "José Portillo", usuario: "sonsonate", password: "1234", role: .gerenteSucursal, stationID: estacionSonsonate.id)
        ]
    }
}

extension FuelType {
    /// Precio de referencia en USD por galón (El Salvador), solo para simular montos en el MVP.
    var precioReferencia: Double {
        switch self {
        case .súper: return 4.10
        case .regular: return 3.95
        case .diésel: return 3.75
        }
    }
}
