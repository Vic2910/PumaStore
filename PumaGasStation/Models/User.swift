//
//  User.swift
//  PumaGasStation
//

import Foundation
import Security

enum UserRole: String, Codable {
    case gerenteGeneral = "Gerente General"
    case gerenteSucursal = "Gerente de Sucursal"
}

struct User: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var nombre: String
    var usuario: String
    var password: String {
        get { CredentialStore.read(id: id) ?? "" }
        set { CredentialStore.write(newValue, id: id) }
    }
    enum CodingKeys: String, CodingKey { case id, nombre, usuario, role, stationID, active }
    var active: Bool? = true
    var isActive: Bool { active != false }
    var role: UserRole
    /// Solo aplica a Gerente de Sucursal: id de la estación asignada.
    var stationID: UUID?

    init(id: UUID = UUID(), nombre: String, usuario: String, password: String, role: UserRole, stationID: UUID? = nil) {
        self.id = id
        self.nombre = nombre
        self.usuario = usuario
        self.role = role
        self.stationID = stationID
        self.password = password
    }
}

private enum CredentialStore {
    static func query(id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.puma.franquicia.credentials",
         kSecAttrAccount as String: id.uuidString]
    }
    static func read(id: UUID) -> String? {
        var attributes = query(id: id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, id: UUID) {
        let attributes = query(id: id)
        let updates = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(attributes as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = attributes
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
