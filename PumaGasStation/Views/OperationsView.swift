import SwiftUI

struct EmployeeAccountView: View {
    let employee: Employee
    @ObservedObject private var remote = SupabaseService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var created = false
    var body: some View { NavigationStack { Form {
        Text(employee.name).bold()
        Text("Cargo: \(employee.position)")
        TextField("Correo de acceso", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
        PasswordInput(title: "Contraseña inicial", text: $password)
        Text("El cargo determina la vista al iniciar sesión. El empleado debe confirmar su correo y entrar con este correo y la contraseña inicial desde la pantalla de inicio de sesión.").font(.caption)
        Button("Crear acceso") { Task { created = await remote.createEmployeeAccount(employee, email: email, password: password); if created { password = "" } } }.disabled(created || remote.busy || email.isEmpty || password.count < 8)
        Text(remote.message).font(.caption)
    }.navigationTitle("Acceso del empleado").onAppear { email = employee.email } } }
}

struct WorkerRegisterView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var remote = SupabaseService.shared
    @State private var cart: [UUID: Int] = [:]
    @State private var fuel = "Súper"
    @State private var gallons = 0.0
    @State private var serviceID: UUID?
    @State private var payment = "Efectivo"
    @State private var received = 0.0
    @State private var saleID = UUID()
    @State private var endConfirmation = false
    @State private var lastSale: RegisterSale?
    private var seller: Bool { remote.profile?.role == "seller" }
    private var session: EmployeeSession? { remote.sessions.first { $0.exited_at == nil } }
    private var total: Double {
        let raw = seller ? (remote.worker?.products ?? []).reduce(0) { $0 + $1.price * Double(cart[$1.id] ?? 0) } : gallons * (remote.prices.first { $0.fuel == fuel }?.price ?? 0) + (remote.worker?.services.first { $0.id == serviceID }?.price ?? 0)
        return (raw * 100).rounded() / 100
    }
    var body: some View { TabView {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 14) {
            Text(remote.worker?.name ?? "Mi sucursal").font(.caption).foregroundStyle(PumaStyle.green)
            Text(authViewModel.currentUser?.nombre ?? "").font(.title2.bold())
            if !seller {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Existencias de combustible").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    if let tanks = remote.worker?.tanks {
                        ForEach(tanks) { tank in
                            VStack(alignment: .leading, spacing: 6) {
                                OperationInfo(label: tank.fuelType.rawValue, value: String(format: "%.2f gal", tank.currentGallons))
                                ProgressView(value: tank.percentage).tint(PumaStyle.green)
                                Text(String(format: "Capacidad: %.0f gal · %.1f%%", tank.capacityGallons, tank.percentage * 100)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } else { Text("Inventario no disponible. Se requiere actualizar la base de datos.").font(.caption) }
                    Button("Actualizar existencias") { Task { await remote.run("pull") } }.disabled(remote.busy)
                }.pumaCard()
            }
            if let session {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Mi jornada · Turno \(session.turn)").font(.subheadline.bold()); Spacer(); OperationBadge(text: "En curso", color: PumaStyle.green) }
                    OperationInfo(label: "Entrada registrada", value: ShiftDisplay.format(session.entered_at, pattern: "dd/MM/yyyy HH:mm"))
                    let sales = remote.registerSales.filter { $0.session_id == session.id }
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text("Ventas del turno").font(.caption).foregroundStyle(.secondary); Text("\(sales.count)").font(.title2.bold()).foregroundStyle(PumaStyle.green) }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) { Text("Total vendido").font(.caption).foregroundStyle(.secondary); Text(PumaStyle.money(sales.reduce(0) { $0 + $1.total })).font(.title2.bold()).foregroundStyle(PumaStyle.green) }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(12).background(PumaStyle.background).clipShape(RoundedRectangle(cornerRadius: 8))
                }.pumaCard()
                if seller {
                    ForEach(remote.worker?.products ?? []) { p in HStack { VStack(alignment: .leading) { Text(p.name).bold(); Text("\(PumaStyle.money(p.price)) · Disponibles: \(p.stock)").font(.caption) }; Spacer(); Stepper("\(cart[p.id] ?? 0)", value: Binding(get: { cart[p.id] ?? 0 }, set: { cart[p.id] = $0 }), in: 0...max(0, p.stock)).fixedSize() }.pumaCard() }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Datos del despacho").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                        Picker("Combustible", selection: $fuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                        Text("Precio por galón: \(PumaStyle.money(remote.prices.first { $0.fuel == fuel }?.price ?? 0))").font(.caption)
                        TextField("Galones", value: $gallons, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        Picker("Servicio adicional", selection: $serviceID) { Text("Sin servicio").tag(UUID?.none); ForEach(remote.worker?.services ?? []) { Text("\($0.name) · \(PumaStyle.money($0.price))").tag(Optional($0.id)) } }
                    }.pumaCard()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pago y resumen").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    OperationInfo(label: "Total", value: PumaStyle.money(total))
                    Picker("Pago", selection: $payment) { Text("Efectivo").tag("Efectivo"); Text("Tarjeta").tag("Tarjeta") }.pickerStyle(.segmented)
                    if payment == "Efectivo" { TextField("Monto recibido", value: $received, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder); OperationInfo(label: "Cambio", value: PumaStyle.money(max(0, received - total))) }
                    Button("Registrar venta") { Task { await sell(session) } }.buttonStyle(.borderedProminent).disabled((seller ? cart.values.allSatisfy({ $0 <= 0 }) : gallons <= 0) || (payment == "Efectivo" && received < total) || (!seller && !remote.prices.contains { $0.fuel == fuel }))
                }.pumaCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cierre de jornada").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    Text("Registra tu salida y guarda el resumen de las ventas de este turno.").font(.caption).foregroundStyle(.secondary)
                    Button("Terminar turno y registrar salida", role: .destructive) { endConfirmation = true }.buttonStyle(.bordered)
                }.pumaCard()
            } else {
                Text("Solo puedes trabajar una jornada por día. Al finalizar, tu resumen queda guardado.").font(.caption).pumaCard()
                Text("El gerente debe asignarte un turno en Personal → Consultar turnos o en Turnos y horarios. Podrás registrar entrada durante ese horario; después se habilitan las ventas.").font(.caption).pumaCard()
                if (remote.worker?.shifts ?? []).isEmpty { Text("Todavía no tienes turnos asignados. Solicita la asignación al gerente.").foregroundStyle(.secondary) }
                ForEach((remote.worker?.shifts ?? []).filter { $0.cancelled != true && $0.clockOut == nil }) { shift in
                    VStack(alignment: .leading) {
                        Text("Turno \(shift.operationalTurn ?? (shift.type == "Mañana" ? 1 : 2))").bold()
                        Text("\(ShiftDisplay.format(shift.start, pattern: "dd/MM/yyyy HH:mm")) → \(ShiftDisplay.format(shift.end, pattern: "dd/MM/yyyy HH:mm"))").font(.caption)
                    }.pumaCard()
                }
                ForEach((remote.worker?.shifts ?? []).filter { shift in
                    let start = ShiftDisplay.date(shift.start), end = ShiftDisplay.date(shift.end)
                    return shift.cancelled != true && shift.clockOut == nil && start <= Date() && end > Date()
                }) { shift in Button("Registrar entrada · Turno \(shift.operationalTurn ?? (shift.type == "Mañana" ? 1 : 2))") { Task { _ = await remote.registerAction("begin_employee_shift", ["p_shift": shift.id.uuidString]) } }.buttonStyle(.borderedProminent) }
                if let finished = remote.sessions.first, let summary = finished.summary { RegisterTotalsView(summary: summary).pumaCard() }
            }
            if let lastSale { VStack(alignment: .leading) { Label("Venta registrada", systemImage: "checkmark.circle.fill").foregroundStyle(PumaStyle.green); RegisterSaleRow(sale: lastSale) }.pumaCard() }
            Text(remote.message).font(.caption).foregroundStyle(.secondary)
            Button("Actualizar mi turno") { Task { await remote.run("pull") } }.disabled(remote.busy)
        }.padding(16) }.pumaPage().navigationTitle(seller ? "Punto de venta" : "Despacho")
            .confirmationDialog("¿Terminar tu turno?", isPresented: $endConfirmation, titleVisibility: .visible) { Button("Terminar y guardar resumen", role: .destructive) { if let session { Task { if await remote.registerAction("end_employee_shift", ["p_session": session.id.uuidString]) { cart = [:]; received = 0; lastSale = nil } } } } } message: { Text("Se registrará tu salida. No podrás abrir otra jornada para este mismo día.") }
        }.tabItem { Label("Mi turno", systemImage: "clock") }
        NavigationStack { WorkerHistoryView() }.tabItem { Label("Mis ventas", systemImage: "receipt") }
        NavigationStack { ProfileView() }.tabItem { Label("Perfil", systemImage: "person") }
    } }
    private func sell(_ session: EmployeeSession) async {
        let requestID = saleID
        let items: [[String: Any]] = cart.filter { $0.value > 0 }.map { ["productID": $0.key.uuidString, "quantity": $0.value] }
        let ok = await remote.registerAction("register_employee_sale", ["p_id": requestID.uuidString, "p_session": session.id.uuidString, "p_items": seller ? items : [], "p_fuel": seller ? NSNull() : fuel as Any, "p_gallons": seller ? 0 : gallons, "p_service": serviceID.map { $0.uuidString as Any } ?? NSNull(), "p_payment": payment, "p_received": payment == "Tarjeta" ? total : received])
        if ok { lastSale = remote.registerSales.first { $0.id == requestID }; saleID = UUID(); cart = [:]; gallons = 0; received = 0; serviceID = nil }
    }
}
struct WorkerHistoryView: View {
    @ObservedObject private var remote = SupabaseService.shared
    @State private var day = Date()
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 12) {
        DatePicker("Día operativo", selection: $day, displayedComponents: .date)
        ForEach(remote.registerSales.filter { $0.work_day == RegisterManagementView.day(day) }) { sale in RegisterSaleRow(sale: sale).pumaCard() }
        Text("Jornadas y resúmenes").font(.headline)
        ForEach(remote.sessions.filter { $0.work_day == RegisterManagementView.day(day) }) { s in VStack(alignment: .leading) { Text("Turno \(s.turn) · \(s.exited_at == nil ? "En curso" : "Terminado")").bold(); Text("Entrada: \(ShiftDisplay.format(s.entered_at, pattern: "dd/MM/yyyy HH:mm"))"); Text("Salida: \(s.exited_at.map { ShiftDisplay.format($0, pattern: "dd/MM/yyyy HH:mm") } ?? "Pendiente")"); if let summary = s.summary { RegisterTotalsView(summary: summary) } }.font(.caption).pumaCard() }
    }.padding(16) }.pumaPage().navigationTitle("Mis ventas e historial").environment(\.timeZone, MockDataService.calendar.timeZone) }
}
struct RegisterSaleRow: View {
    let sale: RegisterSale
    var body: some View { VStack(alignment: .leading, spacing: 5) {
        Text("\(sale.employee_name) · Turno \(sale.turn)").font(.subheadline.bold())
        Text(ShiftDisplay.format(sale.sold_at, pattern: "dd/MM/yyyy HH:mm")).font(.caption)
        if let fuel = sale.fuel { Text("\(fuel) · \(sale.gallons, specifier: "%.2f") gal · \(PumaStyle.money(sale.fuel_total))").font(.caption) }
        ForEach(Array(sale.lines.enumerated()), id: \.offset) { _, l in Text("\(l.quantity) × \(l.name) · \(PumaStyle.money(l.total))").font(.caption) }
        if sale.service_id != nil { Text("Servicio: \(PumaStyle.money(sale.service_total))").font(.caption) }
        OperationInfo(label: "Total · \(sale.payment)", value: PumaStyle.money(sale.total))
        OperationInfo(label: "Recibido / cambio", value: "\(PumaStyle.money(sale.received)) / \(PumaStyle.money(sale.change))")
    } }
}
struct RegisterTotalsView: View {
    let summary: RegisterSummary
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        OperationInfo(label: "Combustible", value: PumaStyle.money(summary.fuel))
        OperationInfo(label: "Productos", value: PumaStyle.money(summary.products))
        OperationInfo(label: "Servicios", value: PumaStyle.money(summary.services))
        OperationInfo(label: "Total del turno", value: PumaStyle.money(summary.total))
        if let sales = summary.sales { Text("\(sales) ventas · \(summary.units ?? 0) unidades").font(.caption) }
        if let cash = summary.cash { OperationInfo(label: "Efectivo", value: PumaStyle.money(cash)); OperationInfo(label: "Tarjeta", value: PumaStyle.money(summary.card ?? 0)) }
        if let total = summary.dayTotal { Divider(); OperationInfo(label: "Combustible acumulado", value: PumaStyle.money(summary.dayFuel ?? 0)); OperationInfo(label: "Productos acumulados", value: PumaStyle.money(summary.dayProducts ?? 0)); OperationInfo(label: "Servicios acumulados", value: PumaStyle.money(summary.dayServices ?? 0)); OperationInfo(label: "Total del día al hacer el corte", value: PumaStyle.money(total)) }
    } }
}
struct RegisterManagementView: View {
    var initialEmployeeID: UUID?
    @ObservedObject private var remote = SupabaseService.shared
    @ObservedObject private var repo = MockDataService.shared
    @ObservedObject private var store = OperationsStore.shared
    @State private var stationID: UUID?
    @State private var employeeID: UUID?
    @State private var date = Date()
    @State private var activity = "Todas"
    @State private var price = 0.0
    @State private var fuel = "Súper"
    @State private var closing: Int?
    @State private var supervisedSession: UUID?
    static func day(_ date: Date) -> String { let f = DateFormatter(); f.timeZone = MockDataService.calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private var selected: UUID? { stationID ?? remote.profile?.station_id ?? repo.stations.first?.id }
    private var day: String { Self.day(date) }
    private var sales: [RegisterSale] { remote.registerSales.filter { $0.station_id == selected && $0.work_day == day && (employeeID == nil || $0.employee_id == employeeID) && (activity == "Todas" || (activity == "Combustible" ? $0.fuel_total > 0 : activity == "Productos" ? $0.product_total > 0 : $0.service_id != nil)) } }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 14) {
        if remote.profile?.role == "general" { Picker("Sucursal", selection: $stationID) { ForEach(repo.stations) { Text($0.nombre).tag(Optional($0.id)) } } }
        DatePicker("Día operativo", selection: $date, in: ...Date(), displayedComponents: .date)
        Picker("Empleado", selection: $employeeID) { Text("Todos").tag(UUID?.none); ForEach(store.data.employees.filter { $0.stationID == selected }) { Text($0.name).tag(Optional($0.id)) } }
        Picker("Actividad", selection: $activity) { ForEach(["Todas", "Combustible", "Productos", "Servicios"], id: \.self) { Text($0) } }
        Text("\(sales.count) ventas · \(PumaStyle.money(sales.reduce(0) { $0 + $1.total }))").bold()
        ForEach(1...2, id: \.self) { turn in
            let records = remote.registerSales.filter { $0.station_id == selected && $0.work_day == day && $0.turn == turn }
            let closed = remote.closures.first { $0.station_id == selected && $0.work_day == day && $0.turn == turn }
            VStack(alignment: .leading, spacing: 10) {
                Text("Turno \(turn) · \(closed == nil ? "Pendiente de corte" : "Cerrado")").bold()
                RegisterTotalsView(summary: closed?.snapshot ?? RegisterSummary(fuel: records.reduce(0) { $0 + $1.fuel_total }, products: records.reduce(0) { $0 + $1.product_total }, services: records.reduce(0) { $0 + $1.service_total }, total: records.reduce(0) { $0 + $1.total }, sales: records.count))
                if closed == nil { Button("Hacer corte del turno \(turn)") { closing = turn }.buttonStyle(.borderedProminent).disabled(selected == nil) }
            }.pumaCard()
        }
        Text("Resúmenes de empleados").font(.headline)
        ForEach(remote.sessions.filter { $0.station_id == selected && $0.work_day == day && (employeeID == nil || $0.employee_id == employeeID) }) { s in VStack(alignment: .leading) { Text(store.data.employees.first { $0.id == s.employee_id }?.name ?? "Empleado").bold(); Text("Turno \(s.turn) · \(s.exited_at == nil ? "En curso" : "Terminado")"); if let summary = s.summary { RegisterTotalsView(summary: summary) }; if s.exited_at == nil { Button("Registrar salida supervisada") { supervisedSession = s.id }.buttonStyle(.bordered) } }.pumaCard() }
        ForEach(sales) { RegisterSaleRow(sale: $0).pumaCard() }
        VStack(alignment: .leading, spacing: 10) { Text("Precios de combustible").bold(); Picker("Combustible", selection: $fuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0.rawValue) } }; Text("Actual: \(PumaStyle.money(remote.prices.first { $0.station_id == selected && $0.fuel == fuel }?.price ?? 0)) por galón").font(.caption); TextField("Nuevo precio por galón", value: $price, format: .number).keyboardType(.decimalPad); Button("Guardar precio") { if let selected { Task { _ = await remote.registerAction("set_fuel_price", ["p_station": selected.uuidString, "p_fuel": fuel, "p_price": price]) } } }.disabled(price <= 0 || !price.isFinite) }.pumaCard()
        Text(remote.message).font(.caption)
    }.padding(16) }.pumaPage().navigationTitle("Ventas y cortes por turno").environment(\.timeZone, MockDataService.calendar.timeZone).onAppear { employeeID = initialEmployeeID }
        .confirmationDialog("¿Cerrar este turno?", isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible) { Button("Confirmar corte", role: .destructive) { if let selected, let turn = closing { Task { _ = await remote.registerAction("close_operational_turn", ["p_station": selected.uuidString, "p_day": day, "p_turn": turn]); closing = nil } } } } message: { Text("Las jornadas del turno deben haber terminado. El corte queda guardado y no puede modificarse.") }
        .confirmationDialog("¿Registrar la salida de este empleado?", isPresented: Binding(get: { supervisedSession != nil }, set: { if !$0 { supervisedSession = nil } }), titleVisibility: .visible) { Button("Registrar salida", role: .destructive) { if let id = supervisedSession { Task { _ = await remote.registerAction("end_employee_shift", ["p_session": id.uuidString]); supervisedSession = nil } } } } message: { Text("Úsalo cuando el empleado no pueda finalizar su jornada. La acción queda registrada con tu cuenta.") }
    }
}

struct OperationsMenuView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        List {
            NavigationLink("Llenar tanques", destination: OperationsWorkspace(module: "Llenar tanques"))
            NavigationLink("Personal", destination: OperationsWorkspace(module: "Personal"))
            NavigationLink("Turnos y horarios", destination: ShiftScheduleView())
            NavigationLink("Inventario comercial", destination: OperationsWorkspace(module: "Productos"))
            NavigationLink("Punto de venta", destination: OperationsWorkspace(module: "Ventas"))
            NavigationLink("Servicios", destination: OperationsWorkspace(module: "Servicios"))
            NavigationLink("Ventas y cortes por turno", destination: RegisterManagementView())
            NavigationLink("Perfil", destination: ProfileView())
        }.navigationTitle("Más").scrollContentBackground(.hidden).pumaPage()
    }
}

struct OperationsWorkspace: View {
    let module: String
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var repo = MockDataService.shared
    @ObservedObject private var store = OperationsStore.shared
    @State private var stationID: UUID?
    @State private var search = ""
    @State private var editor: String?
    @State private var employee: Employee?
    @State private var product: CommercialProduct?
    @State private var service: ExtraService?
    @State private var cart: [UUID: Int] = [:]
    @State private var received = 0.0
    @State private var payment = "Efectivo"
    @State private var employeeState = "Todos"
    @State private var categoryFilter = "Todos"
    @State private var showHistory = false
    @State private var lastSale: CommercialSale?
    private var branches: [Station] { repo.stations.filter { authViewModel.currentUser?.role == .gerenteGeneral || $0.id == authViewModel.currentUser?.stationID } }
    private var selectedID: UUID? { stationID ?? branches.first?.id }
    private var employees: [Employee] { store.data.employees.filter { $0.stationID == selectedID } }
    private var products: [CommercialProduct] { store.data.products.filter { $0.stationID == selectedID } }
    private var total: Double { products.reduce(0) { $0 + $1.price * Double(cart[$1.id] ?? 0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if branches.count > 1 { Picker("Sucursal", selection: $stationID) { ForEach(branches) { Text($0.nombre).tag(Optional($0.id)) } }.onChange(of: stationID) { _, _ in cart = [:]; lastSale = nil; received = 0 } }
                Text(branches.first { $0.id == selectedID }?.nombre ?? "Sin sucursal asignada").font(.caption).foregroundStyle(PumaStyle.green)
                if selectedID != nil {
                    if module == "Personal" { personnel }
                    else if module == "Turnos" { shifts }
                    else if module == "Productos" { catalog }
                    else if module == "Ventas" { sales }
                    else if module == "Servicios" { services }
                    else { tanks }
                }
            }.padding(16)
        }.navigationTitle(module == "Productos" ? "Inventario comercial" : module == "Ventas" ? "Punto de venta" : module).navigationBarTitleDisplayMode(.inline).pumaPage()
            .sheet(item: Binding(get: { editor.map { EditorKind(id: $0) } }, set: { editor = $0?.id })) { kind in
                if let id = selectedID { OperationEditor(kind: kind.id, stationID: id, employee: employee, product: product, service: service) }
            }
            .alert("No se pudo guardar", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("Aceptar") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private func open(_ kind: String) { editor = kind }
    private var personnel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("+ Registrar empleado") { employee = nil; open("Empleado") }.buttonStyle(.borderedProminent)
            TextField("Buscar por nombre o documento", text: $search).textFieldStyle(.roundedBorder)
            Picker("Estado", selection: $employeeState) { ForEach(["Todos", "Activo", "Inactivo"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            Text("\(employees.count) empleados · \(employees.filter { $0.active }.count) activos · \(employees.filter { !$0.active }.count) inactivos").font(.caption2).foregroundStyle(.secondary)
            ForEach(employees.filter { (employeeState == "Todos" || ($0.active ? "Activo" : "Inactivo") == employeeState) && (search.isEmpty || "\($0.name) \($0.document)".localizedCaseInsensitiveContains(search)) }) { e in
                NavigationLink { PersonnelDetailView(employeeID: e.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(e.name).font(.subheadline.bold()); Spacer(); OperationBadge(text: e.active ? "Activo" : "Inactivo", color: e.active ? PumaStyle.green : .red) }
                        Text("EMP-\(e.id.uuidString.prefix(6)) · \(e.position)").font(.caption2).foregroundStyle(.secondary)
                        HStack { Text(branches.first { $0.id == e.stationID }?.nombre ?? "").font(.caption).foregroundStyle(PumaStyle.green); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                    }.pumaCard()
                }.buttonStyle(.plain)
            }
        }
    }
    private var shifts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("+ Asignar turno") { open("Turno") }.buttonStyle(.borderedProminent)
            ForEach(store.data.shifts.filter { $0.stationID == selectedID }.sorted { $0.start > $1.start }) { shift in
                VStack(alignment: .leading, spacing: 8) {
                    Text(employees.first { $0.id == shift.employeeID }?.name ?? "Empleado").bold()
                    Text("\(shift.start) → \(shift.end)").font(.caption)
                    Text("Entrada: \(shift.clockIn ?? "Pendiente")\nSalida: \(shift.clockOut ?? "Pendiente")").font(.caption)
                    Button(shift.clockIn == nil ? "Registrar entrada" : "Registrar salida") { Task { _ = await SupabaseService.shared.perform { store.clock(shift.id) } } }.disabled(shift.clockOut != nil)
                }.pumaCard()
            }
        }
    }
    private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("+ Nuevo producto") { product = nil; open("Producto") }.buttonStyle(.borderedProminent)
            TextField("Buscar producto o SKU", text: $search).textFieldStyle(.roundedBorder)
            Picker("Categoría", selection: $categoryFilter) { ForEach(["Todos", "Conveniencia", "Lubricantes"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if products.contains(where: { $0.stock <= $0.minimum }) { Label("\(products.filter { $0.stock <= $0.minimum }.count) alertas de stock", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).pumaCard() }
            ForEach(products.filter { (categoryFilter == "Todos" || $0.category == categoryFilter) && (search.isEmpty || "\($0.name) \($0.sku)".localizedCaseInsensitiveContains(search)) }) { p in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(p.name).bold(); Spacer(); Text(PumaStyle.money(p.price)).foregroundStyle(PumaStyle.green) }
                    Text("\(p.sku) · \(p.category) · Stock: \(p.stock)").font(.caption)
                    OperationBadge(text: p.stock == 0 ? "Agotado" : p.stock <= p.minimum ? "Stock bajo" : p.active ? "Disponible" : "Inactivo", color: p.stock == 0 ? .red : p.stock <= p.minimum ? .orange : PumaStyle.green)
                    Button("Editar producto") { product = p; open("Producto") }
                }.pumaCard()
            }
            HStack { NavigationLink("Punto de venta") { OperationsWorkspace(module: "Ventas") }; Spacer(); NavigationLink("Historial") { CommercialHistoryView(stationID: selectedID) } }.font(.subheadline).pumaCard()
        }
    }
    private var sales: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sale = lastSale {
                VStack(spacing: 10) { Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(PumaStyle.green); Text("Venta registrada").font(.headline); Text("Guardada correctamente").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).pumaCard()
                CommercialSaleSummary(sale: sale)
                Button("+ Nueva venta") { lastSale = nil }.buttonStyle(.borderedProminent)
            } else {
            TextField("Buscar producto o SKU", text: $search).textFieldStyle(.roundedBorder)
            Text("Productos disponibles").font(.headline).foregroundStyle(PumaStyle.green)
            ForEach(products.filter { $0.active && (search.isEmpty || "\($0.name) \($0.sku)".localizedCaseInsensitiveContains(search)) }) { p in
                HStack { Text(p.name); Spacer(); Stepper("\(cart[p.id] ?? 0)", value: Binding(get: { cart[p.id] ?? 0 }, set: { if $0 == 0 { cart.removeValue(forKey: p.id) } else { cart[p.id] = $0 } }), in: 0...max(0, p.stock)) }.pumaCard()
            }
            Text("Carrito · \(cart.values.reduce(0, +)) unidades").font(.headline).foregroundStyle(PumaStyle.green)
            ForEach(products.filter { (cart[$0.id] ?? 0) > 0 }) { p in HStack { Text("\(cart[p.id] ?? 0) × \(p.name)"); Spacer(); Text(PumaStyle.money(p.price * Double(cart[p.id] ?? 0))) }.font(.caption).pumaCard() }
            Text("Total: \(PumaStyle.money(total))").font(.title3.bold()).foregroundStyle(PumaStyle.green)
            Picker("Pago", selection: $payment) { Text("Efectivo").tag("Efectivo"); Text("Tarjeta").tag("Tarjeta") }
            TextField("Recibido USD", value: $received, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            Button("Confirmar venta · \(PumaStyle.money(total))") { Task { if let id = selectedID, await SupabaseService.shared.perform({ store.sell(stationID: id, quantities: cart, cashier: authViewModel.currentUser?.nombre ?? "", payment: payment, received: received) }) { lastSale = store.data.sales.last { $0.stationID == id }; cart = [:]; received = 0 } } }.buttonStyle(.borderedProminent).disabled(cart.isEmpty)
            }
            NavigationLink("Historial de ventas") { CommercialHistoryView(stationID: selectedID) }.buttonStyle(.bordered)
        }
    }
    private var services: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("+ Definir servicio") { service = nil; open("Servicio") }.buttonStyle(.borderedProminent)
            Picker("Vista", selection: $showHistory) { Text("Catálogo").tag(false); Text("Historial").tag(true) }.pickerStyle(.segmented)
            if !showHistory {
            Text("\(store.data.services.filter { $0.stationID == selectedID && $0.available }.count) servicios disponibles").font(.caption2).foregroundStyle(.secondary)
            ForEach(store.data.services.filter { $0.stationID == selectedID }) { s in
                VStack(alignment: .leading, spacing: 8) {
                    Label(s.name, systemImage: "wrench.and.screwdriver").bold().foregroundStyle(PumaStyle.green); Text("Precio registrado · \(PumaStyle.money(s.price))").font(.caption)
                    OperationBadge(text: s.available ? "Disponible" : "No disponible", color: s.available ? PumaStyle.green : .gray)
                    HStack { Button("Editar precio / disponibilidad") { service = s; open("Servicio") }; Button("Registrar") { service = s; open("Registro") }.disabled(!s.available) }.font(.caption)
                }.pumaCard()
            }
            } else {
            Text("Historial de servicios").font(.headline)
            ForEach(store.data.records.filter { $0.stationID == selectedID }.reversed()) { r in
                NavigationLink { ServiceRecordDetailView(recordID: r.id) } label: { VStack(alignment: .leading, spacing: 8) {
                    Text("\(r.name) · \(r.status)").bold(); Text("\(r.date) · \(r.vehicle) · \(PumaStyle.money(r.price))").font(.caption)
                    Text(r.notes).font(.caption)
                }.pumaCard() }.buttonStyle(.plain)
            }
            }
        }
    }
    private var tanks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("+ Registrar llenado") { open("Llenado") }.buttonStyle(.borderedProminent)
            if let station = repo.stations.first(where: { $0.id == selectedID }) {
                ForEach(station.tanks) { tank in
                    VStack(alignment: .leading) { Text(tank.fuelType.rawValue).bold(); Text("\(tank.currentGallons.formatted()) / \(tank.capacityGallons.formatted()) gal · \(Int(tank.percentage * 100))%"); ProgressView(value: tank.percentage) }.pumaCard()
                }
                ForEach(station.receipts.reversed()) { receipt in Text("\(receipt.date) · \(receipt.fuel.rawValue) · \(receipt.volume.formatted()) gal · \(receipt.supplier)").font(.caption).pumaCard() }
            }
            Text("El llenado actualiza existencias inmediatamente. No debe registrarse otra vez en un corte.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct EditorKind: Identifiable { var id: String }

struct OperationBadge: View {
    let text: String
    var color: Color = PumaStyle.green
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 5)) }
}

private struct OperationInfo: View {
    let label: String
    let value: String
    var body: some View { HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.caption).padding(.vertical, 5) }
}

struct PersonnelDetailView: View {
    @State private var account = false
    let employeeID: UUID
    @ObservedObject private var store = OperationsStore.shared
    @State private var editing = false
    @State private var confirmDeactivation = false
    private var employee: Employee? { store.data.employees.first { $0.id == employeeID } }
    var body: some View {
        ScrollView { if let e = employee { VStack(alignment: .leading, spacing: 14) {
            HStack { Text(e.name.prefix(2).uppercased()).font(.headline).foregroundStyle(PumaStyle.green).padding(12).background(PumaStyle.green.opacity(0.1)).clipShape(Circle()); VStack(alignment: .leading) { Text(e.name).bold(); Text("EMP-\(e.id.uuidString.prefix(6)) · \(e.position)").font(.caption2).foregroundStyle(.secondary) }; Spacer(); OperationBadge(text: e.active ? "Activo" : "Inactivo", color: e.active ? PumaStyle.green : .red) }.pumaCard().overlay(RoundedRectangle(cornerRadius: 12).stroke(PumaStyle.green))
            VStack(alignment: .leading) { Text("Datos personales").font(.headline).foregroundStyle(PumaStyle.green); OperationInfo(label: "Nombre", value: e.name); OperationInfo(label: "Documento", value: e.document); OperationInfo(label: "Teléfono", value: e.phone); OperationInfo(label: "Correo", value: e.email.isEmpty ? "Sin registrar" : e.email) }.pumaCard()
            VStack(alignment: .leading) { Text("Asignación laboral").font(.headline).foregroundStyle(PumaStyle.green); OperationInfo(label: "Sucursal", value: MockDataService.shared.stations.first { $0.id == e.stationID }?.nombre ?? ""); OperationInfo(label: "Cargo", value: e.position); OperationInfo(label: "Ingreso", value: ShiftDisplay.format(e.hireDate, pattern: "dd/MM/yyyy")); NavigationLink("Consultar turnos e historial") { ShiftScheduleView(initialStationID: e.stationID, initialEmployeeID: e.id, initialHistory: true) }.buttonStyle(.bordered) }.pumaCard()
            VStack(alignment: .leading, spacing: 10) { Text("Estado del empleado").font(.headline); Button(e.active ? "Desactivar" : "Activar", role: e.active ? .destructive : nil) { if e.active { confirmDeactivation = true } else { setActive(true) } }.buttonStyle(.bordered) }.pumaCard()
            if ["vendedor", "despachador"].contains(e.position.lowercased()) { Button("Crear acceso del empleado") { account = true }.buttonStyle(.bordered); NavigationLink("Ventas del empleado") { RegisterManagementView(initialEmployeeID: e.id) } }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(16) } }.pumaPage().navigationTitle("Detalle de empleado").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { Button("Modificar datos") { editing = true }.buttonStyle(.borderedProminent).padding(16).frame(maxWidth: .infinity).background(PumaStyle.background) }
            .sheet(isPresented: $account) { if let e = employee { EmployeeAccountView(employee: e) } }
            .sheet(isPresented: $editing) { if let e = employee { OperationEditor(kind: "Empleado", stationID: e.stationID, employee: e) } }
            .confirmationDialog("¿Desactivar empleado?", isPresented: $confirmDeactivation, titleVisibility: .visible) { Button("Desactivar", role: .destructive) { setActive(false) } } message: { Text("No podrá recibir nuevos turnos. Revisa sus turnos pendientes.") }
    }
    private func setActive(_ active: Bool) { guard var e = employee else { return }; e.active = active; Task { _ = await SupabaseService.shared.perform { store.saveEmployee(e) } } }
}

struct CommercialSaleSummary: View {
    let sale: CommercialSale
    var body: some View { VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading) { HStack { Text("Venta V-\(sale.id.uuidString.prefix(6))").bold(); Spacer(); OperationBadge(text: "Confirmada") }; OperationInfo(label: "Fecha", value: ShiftDisplay.format(sale.date, pattern: "dd/MM/yyyy · HH:mm")); OperationInfo(label: "Cajero", value: sale.cashier) }.pumaCard()
        VStack(alignment: .leading) { Text("Artículos vendidos").font(.headline).foregroundStyle(PumaStyle.green); ForEach(Array(sale.lines.enumerated()), id: \.offset) { _, line in OperationInfo(label: "\(line.quantity) × \(line.name)", value: PumaStyle.money(line.total)) }; OperationInfo(label: "Total · \(sale.lines.reduce(0) { $0 + $1.quantity }) unidades", value: PumaStyle.money(sale.total)) }.pumaCard()
        VStack(alignment: .leading) { Text("Pago").font(.headline).foregroundStyle(PumaStyle.green); OperationInfo(label: "Método", value: sale.payment); OperationInfo(label: "Recibido", value: PumaStyle.money(sale.received)); OperationInfo(label: "Cambio", value: PumaStyle.money(sale.change)) }.pumaCard()
    } }
}

struct CommercialHistoryView: View {
    let stationID: UUID?
    @ObservedObject private var store = OperationsStore.shared
    @State private var search = ""
    private var sales: [CommercialSale] { store.data.sales.filter { $0.stationID == stationID && (search.isEmpty || "\($0.id) \($0.cashier)".localizedCaseInsensitiveContains(search)) }.sorted { $0.date > $1.date } }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 12) {
        TextField("Buscar número de venta o cajero", text: $search).textFieldStyle(.roundedBorder)
        HStack { Text("Ventas: \(sales.count)"); Spacer(); Text(PumaStyle.money(sales.reduce(0) { $0 + $1.total })).foregroundStyle(PumaStyle.green) }.pumaCard()
        ForEach(sales) { sale in NavigationLink { ScrollView { CommercialSaleSummary(sale: sale).padding(16) }.pumaPage().navigationTitle("Detalle de venta") } label: { VStack(alignment: .leading, spacing: 6) { HStack { Text("V-\(sale.id.uuidString.prefix(6))").bold(); Spacer(); OperationBadge(text: "Confirmada") }; Text("\(ShiftDisplay.format(sale.date, pattern: "dd/MM/yyyy · HH:mm")) · \(sale.cashier)").font(.caption2).foregroundStyle(.secondary); Text(PumaStyle.money(sale.total)).foregroundStyle(PumaStyle.green) }.pumaCard() }.buttonStyle(.plain) }
    }.padding(16) }.pumaPage().navigationTitle("Historial de ventas").navigationBarTitleDisplayMode(.inline) }
}

struct ServiceRecordDetailView: View {
    let recordID: UUID
    @ObservedObject private var store = OperationsStore.shared
    @State private var cancelling = false
    private var record: ServiceRecord? { store.data.records.first { $0.id == recordID } }
    var body: some View { ScrollView { if let r = record { VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) { Label(r.name, systemImage: "wrench.and.screwdriver").bold(); HStack { OperationBadge(text: r.status, color: r.status == "Cancelado" ? .red : r.status == "En proceso" ? .blue : PumaStyle.green); Spacer(); Text(PumaStyle.money(r.price)).bold().foregroundStyle(PumaStyle.green) } }.pumaCard().overlay(RoundedRectangle(cornerRadius: 12).stroke(PumaStyle.green))
        VStack(alignment: .leading) { Text("Datos del registro").font(.headline).foregroundStyle(PumaStyle.green); OperationInfo(label: "Sucursal", value: MockDataService.shared.stations.first { $0.id == r.stationID }?.nombre ?? ""); OperationInfo(label: "Fecha", value: ShiftDisplay.format(r.date, pattern: "dd/MM/yyyy · HH:mm")); OperationInfo(label: "Empleado", value: store.data.employees.first { $0.id == r.employeeID }?.name ?? ""); OperationInfo(label: "Vehículo", value: r.vehicle.isEmpty ? "Sin registrar" : r.vehicle) }.pumaCard()
        VStack(alignment: .leading) { Text("Observaciones").font(.headline).foregroundStyle(PumaStyle.green); Text(r.notes.isEmpty ? "Sin observaciones" : r.notes).font(.caption) }.pumaCard()
        if ["Pendiente", "En proceso"].contains(r.status) { HStack { Button(r.status == "Pendiente" ? "Iniciar servicio" : "Completar") { transition(r.status == "Pendiente" ? "En proceso" : "Completado") }.buttonStyle(.borderedProminent); Button("Cancelar", role: .destructive) { cancelling = true }.buttonStyle(.bordered) } }
        if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
    }.padding(16) } }.pumaPage().navigationTitle("Detalle del servicio").navigationBarTitleDisplayMode(.inline).confirmationDialog("¿Cancelar este servicio?", isPresented: $cancelling, titleVisibility: .visible) { Button("Cancelar servicio", role: .destructive) { transition("Cancelado") } } }
    private func transition(_ status: String) { Task { _ = await SupabaseService.shared.perform { store.transition(recordID, to: status) } } }
}

struct DatabaseConnectionView: View {
    @ObservedObject private var remote = SupabaseService.shared
    var body: some View { Form { Text(remote.message); Button("Actualizar datos") { Task { await remote.run("pull") } }.disabled(remote.profile == nil || remote.busy) }.navigationTitle("Conexión") }
}

struct OperationEditor: View {
    let kind: String
    let stationID: UUID
    var employee: Employee?
    var product: CommercialProduct?
    var service: ExtraService?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = OperationsStore.shared
    @State private var name = ""
    @State private var document = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var position = "Cajero"
    @State private var sku = ""
    @State private var category = "Conveniencia"
    @State private var price = 0.0
    @State private var cost = 0.0
    @State private var stock = 0
    @State private var minimum = 0
    @State private var active = true
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(8 * 3600)
    @State private var employeeID: UUID?
    @State private var vehicle = ""
    @State private var notes = ""
    @State private var fuel = FuelType.regular
    @State private var volume = 0.0
    @State private var pressure = ""
    var body: some View {
        NavigationStack {
            Form {
                if kind == "Empleado" {
                    Section("Datos personales") { TextField("Nombre completo *", text: $name); TextField("Documento *", text: $document); TextField("Teléfono *", text: $phone); TextField("Correo (opcional)", text: $email) }
                    Section("Datos laborales") {
                        Picker("Cargo *", selection: $position) {
                            ForEach(Array(Set(["Cajero", "Vendedor", "Despachador", "Operario de servicios", "Supervisor", position])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        Text("Vendedor y Despachador permiten crear una cuenta de acceso desde el detalle del empleado.").font(.caption).foregroundStyle(.secondary)
                        DatePicker("Fecha de ingreso", selection: $start, displayedComponents: .date)
                        Toggle("Activo", isOn: $active)
                    }
                } else if kind == "Producto" {
                    Section("Identificación") { TextField("Nombre *", text: $name); TextField("SKU *", text: $sku); Picker("Categoría", selection: $category) { Text("Conveniencia").tag("Conveniencia"); Text("Lubricantes").tag("Lubricantes") } }
                    Section("Precio y existencias") { TextField("Venta USD", value: $price, format: .number); TextField("Costo USD", value: $cost, format: .number); Stepper("Stock: \(stock)", value: $stock, in: 0...1000000); Stepper("Mínimo: \(minimum)", value: $minimum, in: 0...1000000); Toggle("Disponible", isOn: $active) }
                } else if kind == "Servicio" { TextField("Nombre del servicio", text: $name); TextField("Precio USD", value: $price, format: .number); Toggle("Disponible", isOn: $active) }
                else if kind == "Turno" || kind == "Registro" {
                    Picker("Empleado", selection: $employeeID) { Text("Seleccionar").tag(UUID?.none); ForEach(store.data.employees.filter { $0.stationID == stationID && $0.active }) { Text($0.name).tag(Optional($0.id)) } }
                    if kind == "Turno" { DatePicker("Inicio", selection: $start); DatePicker("Fin", selection: $end) }
                    else {
                        Section("Datos del servicio") { Text(service?.name ?? "Servicio"); Text("Importe: \(PumaStyle.money(service?.price ?? 0))").foregroundStyle(PumaStyle.green) }
                        Section("Datos del vehículo") { TextField("Vehículo", text: $vehicle); TextField("Observaciones", text: $notes, axis: .vertical) }
                        if service?.name.localizedCaseInsensitiveContains("aire") == true { Section("Presión de neumáticos") { TextField("Presión registrada (PSI)", text: $pressure).keyboardType(.decimalPad) } }
                    }
                } else {
                    Picker("Combustible", selection: $fuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Galones recibidos", value: $volume, format: .number); TextField("Costo total USD", value: $cost, format: .number); TextField("Proveedor", text: $name)
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).pumaPage().navigationTitle(editorTitle).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { HStack { Button("Cancelar") { dismiss() }.buttonStyle(.bordered); Button("Guardar cambios") { Task { if await SupabaseService.shared.perform({ save() }) { dismiss() } } }.buttonStyle(.borderedProminent) }.padding(16).frame(maxWidth: .infinity).background(PumaStyle.background) }
                .onAppear {
                    if let e = employee { name = e.name; document = e.document; phone = e.phone; email = e.email; position = e.position; active = e.active; start = ISO8601DateFormatter().date(from: e.hireDate) ?? Date() }
                    if let p = product { name = p.name; sku = p.sku; category = p.category; price = p.price; cost = p.cost; stock = p.stock; minimum = p.minimum; active = p.active }
                    if let s = service { name = s.name; price = s.price; active = s.available }
                }
        }.tint(PumaStyle.green)
    }
    private var editorTitle: String {
        if kind == "Empleado" { return employee == nil ? "Registrar empleado" : "Editar empleado" }
        if kind == "Producto" { return "Producto comercial" }
        if kind == "Registro" { return "Registrar servicio" }
        if kind == "Llenado" { return "Registrar llenado" }
        return "Definir servicio"
    }
    private func save() -> Bool {
        store.error = nil
        var ok = false
        if kind == "Empleado" { ok = store.saveEmployee(Employee(id: employee?.id ?? UUID(), stationID: stationID, name: name, document: document, phone: phone, email: email, position: position, hireDate: OperationsStore.stamp(start), active: active)) }
        else if kind == "Producto" { ok = store.saveProduct(CommercialProduct(id: product?.id ?? UUID(), stationID: stationID, name: name, sku: sku, category: category, price: price, cost: cost, stock: stock, minimum: minimum, active: active)) }
        else if kind == "Servicio" { ok = store.saveService(ExtraService(id: service?.id ?? UUID(), stationID: stationID, name: name, price: price, available: active)) }
        else if kind == "Turno", let employeeID { ok = store.saveShift(WorkShift(stationID: stationID, employeeID: employeeID, start: OperationsStore.stamp(start), end: OperationsStore.stamp(end))) }
        else if kind == "Registro", let employeeID, let service {
            if !pressure.isEmpty && (Double(pressure) == nil || (Double(pressure) ?? -1) < 0) { store.error = "Introduce una presión válida."; return false }
            let observations = [pressure.isEmpty ? "" : "Presión registrada: \(pressure) PSI", notes].filter { !$0.isEmpty }.joined(separator: ". ")
            ok = store.registerService(ServiceRecord(stationID: stationID, serviceID: service.id, name: service.name, employeeID: employeeID, date: OperationsStore.stamp(), price: service.price, vehicle: vehicle, notes: observations))
        }
        else if kind == "Llenado" { ok = store.fill(stationID: stationID, fuel: fuel, volume: volume, cost: cost, supplier: name) }
        if !ok && store.error == nil { store.error = "Selecciona un empleado." }; return ok
    }
}
