import Foundation
import Combine

struct RemoteProfile: Identifiable, Codable {
    var id: UUID
    var name: String
    var role: String
    var station_id: UUID?
    var active: Bool
    var employee_id: UUID?
}
struct StationDocument: Codable { var station: Station; var operations: OperationsData }
struct RemoteStation: Codable { var id: UUID; var revision: Int; var document: StationDocument }
private struct RemoteRevision: Codable { var id: UUID; var revision: Int }

@MainActor final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    @Published var url = UserDefaults.standard.string(forKey: "supabaseURL") ?? "https://zosfnegonmppfoqbpbow.supabase.co"
    @Published var publicKey = UserDefaults.standard.string(forKey: "supabaseKey") ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpvc2ZuZWdvbm1wcGZvcWJwYm93Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1NzIwMDEsImV4cCI6MjEwNzE0ODAwMX0.U_ezjP7NIMtKES9LTFUN0MXXrGQzYAtFo_14tOHKUsA"
    @Published private(set) var profile: RemoteProfile?
    @Published private(set) var profiles: [RemoteProfile] = []
    @Published var message = "Inicia sesión para consultar tus datos."
    @Published var busy = false
    @Published private(set) var sessions: [EmployeeSession] = []
    @Published private(set) var registerSales: [RegisterSale] = []
    @Published private(set) var closures: [OperationalClosure] = []
    @Published private(set) var prices: [FuelPrice] = []
    @Published private(set) var worker: WorkerContext?
    private var token: String?
    private var revisions: [UUID: Int] = [:]
    private var baseDocuments: [UUID: Data] = [:]
    private var hasLoaded = false
    private var refreshToken: String?
    private var refreshTask: Task<Void, Never>?
    private weak var auth: AuthViewModel?
    private func request(_ path: String, method: String = "GET", body: Data? = nil, retry: Bool = true) async throws -> Data {
        guard let endpoint = URL(string: url + path), endpoint.scheme == "https", !publicKey.isEmpty else { throw MockDataService.StoreError.invalid("El servicio no está disponible. Contacta al administrador.") }
        var request = URLRequest(url: endpoint); request.httpMethod = method; request.httpBody = body
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? publicKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, response.statusCode == 401, retry, !path.hasPrefix("/auth/"), let refreshToken {
            let refresh = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            let renewed = try await self.request("/auth/v1/token?grant_type=refresh_token", method: "POST", body: refresh, retry: false)
            let session = try JSONSerialization.jsonObject(with: renewed) as? [String: Any]
            token = session?["access_token"] as? String; self.refreshToken = session?["refresh_token"] as? String
            return try await self.request(path, method: method, body: body, retry: false)
        }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if error?["error_code"] as? String == "email_not_confirmed" {
                throw MockDataService.StoreError.invalid("Confirma tu correo antes de iniciar sesión. Revisa el mensaje de confirmación en tu bandeja de entrada o spam y abre el enlace de confirmación. Después vuelve a iniciar sesión.")
            }
            throw MockDataService.StoreError.invalid(Self.safeRemoteMessage(error, status: (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        return data
    }
    func login(email: String, password: String, auth: AuthViewModel) async {
        busy = true; defer { busy = false }
        do {
            refreshTask?.cancel(); refreshTask = nil; auth.currentUser = nil; refreshToken = nil
            token = nil; profile = nil; revisions = [:]; baseDocuments = [:]; hasLoaded = false
            let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let data = try await request("/auth/v1/token?grant_type=password", method: "POST", body: body)
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            token = response?["access_token"] as? String
            refreshToken = response?["refresh_token"] as? String
            guard token != nil else { throw MockDataService.StoreError.invalid("Sesión inválida.") }
            let rows = try JSONDecoder().decode([RemoteProfile].self, from: await request("/rest/v1/profiles?select=*"))
            let authUser = response?["user"] as? [String: Any]
            guard let id = authUser?["id"] as? String, let own = rows.first(where: { $0.id.uuidString.lowercased() == id.lowercased() && $0.active }) else { throw MockDataService.StoreError.invalid("Perfil inactivo o no provisionado.") }
            profile = own; profiles = rows
            self.auth = auth
            UserDefaults.standard.set(url, forKey: "supabaseURL"); UserDefaults.standard.set(publicKey, forKey: "supabaseKey")
            try await pull()
            MockDataService.shared.users = rows.map { User(id: $0.id, nombre: $0.name, usuario: $0.id.uuidString, password: "", role: UserRole.remote($0.role), stationID: $0.station_id) }
            for index in MockDataService.shared.users.indices { MockDataService.shared.users[index].active = rows[index].active }
            auth.currentUser = User(id: own.id, nombre: own.name, usuario: email, password: "", role: UserRole.remote(own.role), stationID: own.station_id)
            message = "Conectado. Los cambios se guardan automáticamente."
            startRefreshing()
        } catch { token = nil; profile = nil; message = Self.friendly(error) }
    }
    /// UI actions commit only after the shared database acknowledges the revision.
    func perform(_ mutation: () -> Bool) async -> Bool {
        guard profile != nil, !busy else { message = "Inicia sesión para guardar."; return false }
        busy = true; defer { busy = false }
        let repo = MockDataService.shared, store = OperationsStore.shared
        let stationsBefore = repo.stations, operationsBefore = store.data
        guard mutation() else { return false }
        do { try await publish(); message = "Guardado correctamente."; return true }
        catch {
            repo.stations = stationsBefore
            do { try repo.persist() } catch { message = "No se pudo restaurar la caché: \(Self.friendly(error))" }
            _ = store.restore(operationsBefore)
            if Self.friendly(error).contains("Los datos cambiaron") { try? await pull() }
            message = Self.friendly(error)
            store.error = "No se pudo guardar. Tus datos del formulario se conservan. \(Self.friendly(error))"
            return false
        }
    }
    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                if !self.busy { await self.run("pull") }
            }
        }
    }
    private func canonical(_ document: StationDocument) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(document) }
    func pull() async throws {
        guard profile != nil else { throw MockDataService.StoreError.invalid("Inicia sesión remota.") }
        let currentProfiles = try JSONDecoder().decode([RemoteProfile].self, from: await request("/rest/v1/profiles?select=*"))
        guard let current = currentProfiles.first(where: { $0.id == profile?.id && $0.active }) else {
            auth?.currentUser = nil; logout(); throw MockDataService.StoreError.invalid("La cuenta fue desactivada. Inicia sesión con una cuenta activa.")
        }
        profile = current; profiles = currentProfiles
        try await pullRegister()
        if current.role == "seller" || current.role == "dispatcher" {
            worker = try JSONDecoder().decode(WorkerContext.self, from: await request("/rest/v1/rpc/worker_context", method: "POST", body: Data("{}".utf8)))
            MockDataService.shared.stations = []
            _ = OperationsStore.shared.restore(OperationsData())
            return
        }
        let rows = try JSONDecoder().decode([RemoteStation].self, from: await request("/rest/v1/station_documents?select=*"))
        let repo = MockDataService.shared, store = OperationsStore.shared
        if hasLoaded && repo.stations.contains(where: { baseDocuments[$0.id] == nil }) {
            throw MockDataService.StoreError.invalid("Hay sucursales locales sin publicar. Publícalas antes de descargar.")
        }
        for row in rows {
            let current = StationDocument(station: repo.station(id: row.id) ?? row.document.station, operations: store.data.forStation(row.id))
            if let base = baseDocuments[row.id], try canonical(current) != base { throw MockDataService.StoreError.invalid("Hay cambios locales. Publícalos antes de descargar.") }
        }
        let previous = repo.stations
        repo.stations = rows.map { $0.document.station }
        do { try repo.persist() } catch { repo.stations = previous; throw error }
        store.error = nil
        guard store.commit({ next in next = OperationsData(); for row in rows { next.replaceStation(row.id, with: row.document.operations) } }) else {
            repo.stations = previous; try repo.persist()
            throw MockDataService.StoreError.invalid(store.error ?? "No se guardaron operaciones.")
        }
        for row in rows { revisions[row.id] = row.revision; baseDocuments[row.id] = try canonical(row.document) }
        hasLoaded = true
        repo.users = currentProfiles.map { item in
            var user = User(id: item.id, nombre: item.name, usuario: item.id.uuidString, password: "", role: UserRole.remote(item.role), stationID: item.station_id)
            user.active = item.active; return user
        }
    }
    func publish() async throws {
        guard let profile else { throw MockDataService.StoreError.invalid("Inicia sesión remota.") }
        guard profile.role == "general" || profile.role == "branch" else { throw MockDataService.StoreError.invalid("Tu cuenta solo puede registrar ventas de su turno.") }
        var changes: [[String: Any]] = []
        var documents: [UUID: Data] = [:]
        for station in MockDataService.shared.stations where profile.role == "general" || station.id == profile.station_id {
            let document = StationDocument(station: station, operations: OperationsStore.shared.data.forStation(station.id))
            let encoded = try canonical(document)
            if baseDocuments[station.id] == encoded { continue }
            let object = try JSONSerialization.jsonObject(with: encoded)
            changes.append(["id": station.id.uuidString, "revision": revisions[station.id] ?? 0, "document": object]); documents[station.id] = encoded
        }
        if changes.isEmpty { return }
        let body = try JSONSerialization.data(withJSONObject: ["p_changes": changes])
        let result = try await request("/rest/v1/rpc/save_stations", method: "POST", body: body)
        let versions = try JSONDecoder().decode([RemoteRevision].self, from: result)
        guard versions.count == changes.count else { throw MockDataService.StoreError.invalid("El servidor no confirmó todos los cambios.") }
        for version in versions { revisions[version.id] = version.revision; baseDocuments[version.id] = documents[version.id] }
    }
    func createManager(name: String, email: String, password: String, stationID: UUID) async -> Bool {
        guard profile?.role == "general", !busy else { message = "Inicia sesión como gerente general."; return false }
        busy = true; defer { busy = false }
        do {
            _ = try await request("/rest/v1/rpc/save_stations", method: "POST", body: JSONSerialization.data(withJSONObject: ["p_changes": []]))
            let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let data = try await request("/auth/v1/signup", method: "POST", body: body)
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let user = result?["user"] as? [String: Any] ?? result
            guard let id = user?["id"] as? String else { throw MockDataService.StoreError.invalid("No se pudo crear la cuenta. Contacta al administrador.") }
            let profileBody = try JSONSerialization.data(withJSONObject: ["p_id": id, "p_name": name, "p_station": stationID.uuidString])
            _ = try await request("/rest/v1/rpc/provision_manager", method: "POST", body: profileBody)
            try await pull(); message = "Gerente creado. Debe confirmar el correo mediante el enlace recibido."; return true
        } catch { message = Self.friendly(error); return false }
    }
    func assignManager(id: UUID, stationID: UUID?) async -> Bool {
        busy = true; defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["p_id": id.uuidString, "p_station": stationID.map { $0.uuidString as Any } ?? NSNull()])
            _ = try await request("/rest/v1/rpc/assign_manager", method: "POST", body: body)
            try await pull(); message = "Asignación guardada."; return true
        } catch { message = Self.friendly(error); return false }
    }
    func setManager(_ id: UUID, active: Bool) async throws {
        guard !busy else { throw MockDataService.StoreError.invalid("Espera a que termine la operación actual.") }
        busy = true; defer { busy = false }
        let body = try JSONSerialization.data(withJSONObject: ["p_id": id.uuidString, "p_active": active])
        _ = try await request("/rest/v1/rpc/set_manager_active", method: "POST", body: body)
        try await pull()
    }
    func deleteManager(_ id: UUID) async throws {
        guard profile?.role == "general", !busy else { throw MockDataService.StoreError.invalid("Inicia sesión como gerente general y espera a que termine la operación actual.") }
        busy = true; defer { busy = false }
        let body = try JSONSerialization.data(withJSONObject: ["p_id": id.uuidString])
        _ = try await request("/rest/v1/rpc/delete_manager", method: "POST", body: body)
        try await pull(); message = "Gerente eliminado. El historial de la sucursal se conserva."
    }
    func run(_ action: String) async {
        busy = true; defer { busy = false }
        do { if action == "push" { try await publish() } else { try await pull() }; message = "Sincronización completada." }
        catch { message = Self.friendly(error) }
    }
    func logout() { sessions = []; registerSales = []; OperationsStore.shared.registerSales = []; closures = []; prices = []; worker = nil; refreshTask?.cancel(); refreshTask = nil; refreshToken = nil; token = nil; profile = nil; profiles = []; revisions = [:]; baseDocuments = [:]; hasLoaded = false; message = "Sesión remota cerrada." }

    static func safeRemoteMessage(_ error: [String: Any]?, status: Int) -> String {
        switch error?["message"] as? String {
        case "EMPLOYEE": return "El empleado no está activo o no tiene una asignación válida. Contacta al gerente."
        case "POSITION": return "El cargo del empleado no corresponde a este acceso. Contacta al gerente."
        case "SHIFT": return "No tienes este turno asignado. Actualiza tus horarios."
        case "FUEL": return "Selecciona el combustible y una cantidad válida de galones."
        case "SERVICE": return "Este servicio ya no está disponible. Actualiza el catálogo."
        case "PRODUCTS": return "Revisa los productos y cantidades del carrito."
        case "PRICE": return "Introduce un precio mayor que cero."
        case "ACCESS": return "Tu cuenta no tiene permiso para realizar esta acción."
        case "STOCK": return "No hay existencias suficientes. Actualiza el catálogo."
        case "PAYMENT": return "Revisa el monto recibido y el método de pago."
        case "FUEL_PRICE": return "El gerente debe configurar el precio de este combustible."
        case "OPEN_SHIFT": return "Hay una jornada abierta. Debe terminarse antes de continuar."
        case "FIRST_CUT": return "Cierra primero el turno 1."
        case "NO_SHIFT": return "Todavía no hay jornadas registradas para este turno."
        case "SHIFT_TIME": return "La entrada solo se puede registrar durante el horario asignado."
        case "SHIFT_CLOSED", "TURN_CLOSED": return "Este turno ya terminó. No se pueden registrar más ventas."
        case "ONE_SHIFT": return "El empleado solo puede tener un turno por día."
        case "LEGACY_CUT", "USE_REGISTER_CUT": return "Usa el corte por turno; esta fecha ya tiene registros de ventas."
        case "REGISTER_SHIFT_IMMUTABLE": return "La jornada ya empezó. Sus marcaciones no se pueden modificar."
        default:
            if (error?["message"] as? String)?.contains("Conflicto de versión") == true { return "Los datos cambiaron. Actualiza y vuelve a intentar." }
            if status == 400 && error?["error_code"] as? String == "invalid_credentials" { return "Correo o contraseña incorrectos." }
            return "No se pudo completar la operación. Actualiza los datos y vuelve a intentar. Si continúa, contacta al administrador."
        }
    }
    static func friendly(_ error: Error) -> String {
        if let value = error as? MockDataService.StoreError { return value.localizedDescription }
        return "No se pudo conectar. Revisa tu conexión y vuelve a intentar."
    }
    private func rpc(_ name: String, _ values: [String: Any]) async throws -> Data {
        try await request("/rest/v1/rpc/" + name, method: "POST", body: JSONSerialization.data(withJSONObject: values))
    }
    private func pullRegister() async throws {
        let context = try JSONDecoder().decode(RegisterContext.self, from: await rpc("register_context", [:]))
        sessions = context.sessions; registerSales = context.sales; prices = context.prices; closures = context.closures
        OperationsStore.shared.registerSales = registerSales
    }
    @discardableResult func registerAction(_ name: String, _ values: [String: Any]) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do { _ = try await rpc(name, values); try await pull(); message = "Guardado correctamente."; return true }
        catch { message = Self.friendly(error); return false }
    }
    func createEmployeeAccount(_ employee: Employee, email: String, password: String) async -> Bool {
        guard !busy, profile?.role == "general" || profile?.role == "branch" else { return false }
        busy = true; defer { busy = false }
        do {
            let result = try JSONSerialization.jsonObject(with: await request("/auth/v1/signup", method: "POST", body: JSONSerialization.data(withJSONObject: ["email": email, "password": password]))) as? [String: Any]
            guard let user = result?["user"] as? [String: Any], let id = user["id"] as? String else { throw MockDataService.StoreError.invalid("No se pudo crear la cuenta.") }
            _ = try await rpc("provision_employee", ["p_id": id, "p_station": employee.stationID.uuidString, "p_employee": employee.id.uuidString, "p_role": employee.position.lowercased() == "vendedor" ? "seller" : "dispatcher"])
            message = "Acceso creado. El empleado debe confirmar su correo antes de iniciar sesión."; return true
        } catch { message = Self.friendly(error); return false }
    }
}
