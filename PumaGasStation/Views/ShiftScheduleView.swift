import SwiftUI

enum ShiftDisplay {
    static let types = ["Mañana", "Tarde", "Noche", "Personalizado"]
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text) ?? .distantPast }
    static func format(_ text: String, pattern: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_SV"); formatter.timeZone = MockDataService.calendar.timeZone; formatter.dateFormat = pattern
        return formatter.string(from: date(text))
    }
    static func code(_ shift: WorkShift) -> String { "TUR-" + shift.id.uuidString.prefix(8) }
    static func duration(_ shift: WorkShift) -> String { String(format: "%.1f h", date(shift.end).timeIntervalSince(date(shift.start)) / 3600) }
    static func overnight(_ shift: WorkShift) -> Bool { !MockDataService.calendar.isDate(date(shift.start), inSameDayAs: date(shift.end)) }
    static func color(_ status: String) -> Color { status == "Cancelado" ? .red : status == "En curso" ? .blue : status == "Completado" ? .gray : PumaStyle.green }
}

struct ShiftScheduleView: View {
    var initialStationID: UUID? = nil
    var initialEmployeeID: UUID? = nil
    var initialHistory = false
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var repo = MockDataService.shared
    @ObservedObject private var store = OperationsStore.shared
    @ObservedObject private var remote = SupabaseService.shared
    @State private var stationID: UUID?
    @State private var employeeID: UUID?
    @State private var status = "Todos"
    @State private var day = Date()
    @State private var assigning = false
    @State private var history = false
    private var stations: [Station] { repo.stations.filter { authViewModel.currentUser?.role == .gerenteGeneral || $0.id == authViewModel.currentUser?.stationID } }
    private var selected: UUID? { stationID ?? stations.first?.id }
    private var employees: [Employee] { store.data.employees.filter { $0.stationID == selected } }
    private var scheduled: [WorkShift] { store.data.shifts.filter { $0.stationID == selected && (history || MockDataService.calendar.isDate(ShiftDisplay.date($0.start), inSameDayAs: day)) && (employeeID == nil || $0.employeeID == employeeID) }.sorted { history ? $0.start > $1.start : $0.start < $1.start } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Turnos y horarios · \(stations.first { $0.id == selected }?.nombre ?? "Sin sucursal")").font(.caption).foregroundStyle(PumaStyle.green)
                Picker("Vista", selection: $history) { Text("Programación").tag(false); Text("Historial").tag(true) }.pickerStyle(.segmented)
                HStack {
                    Picker("Sucursal", selection: $stationID) { ForEach(stations) { Text($0.nombre).tag(Optional($0.id)) } }
                    if !history { DatePicker("Fecha", selection: $day, displayedComponents: .date).labelsHidden() }
                }.font(.caption)
                HStack {
                    Picker("Empleado", selection: $employeeID) { Text("Todos").tag(UUID?.none); ForEach(employees) { Text($0.name).tag(Optional($0.id)) } }
                    Picker("Estado", selection: $status) { ForEach(["Todos", "Programado", "En curso", "Completado", "Cancelado"], id: \.self) { Text($0) } }
                }.font(.caption)
                HStack {
                    ForEach(["Programado", "En curso", "Completado", "Cancelado"], id: \.self) { value in
                        VStack(spacing: 5) { Text("\(scheduled.filter { $0.status == value }.count)").bold().foregroundStyle(ShiftDisplay.color(value)); Text(value).font(.system(size: 9)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
                    }
                }.pumaCard()
                Text("\(scheduled.count) turnos · Hora de El Salvador (UTC−6)").font(.caption2).foregroundStyle(.secondary)
                ForEach(scheduled.filter { status == "Todos" || $0.status == status }) { shift in
                    NavigationLink { ShiftDetailView(shiftID: shift.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(employees.first { $0.id == shift.employeeID }?.name ?? "Empleado").font(.subheadline.bold()); Spacer(); shiftBadge(shift.status) }
                            Text("\(ShiftDisplay.code(shift)) · \(employees.first { $0.id == shift.employeeID }?.position ?? "")").font(.caption2).foregroundStyle(.secondary)
                            if history { Text(ShiftDisplay.format(shift.start, pattern: "dd/MM/yyyy")).font(.caption).foregroundStyle(.secondary) }
                            HStack { Text("\(ShiftDisplay.format(shift.start, pattern: "HH:mm"))–\(ShiftDisplay.format(shift.end, pattern: "HH:mm")) · \(shift.type ?? "Personalizado") · \(ShiftDisplay.duration(shift))").font(.caption).foregroundStyle(PumaStyle.green); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                            if ShiftDisplay.overnight(shift) { Text("Salida: \(ShiftDisplay.format(shift.end, pattern: "dd/MM/yyyy")) (+1 día)").font(.caption2).foregroundStyle(PumaStyle.green) }
                        }.pumaCard()
                    }.buttonStyle(.plain)
                }
                if scheduled.isEmpty { ContentUnavailableView("Sin turnos para esta fecha", systemImage: "calendar", description: Text("Asigna un turno a un empleado activo.")) }
            }.padding(16)
        }.pumaPage().navigationTitle("Programación de turnos").navigationBarTitleDisplayMode(.inline)
            .environment(\.timeZone, MockDataService.calendar.timeZone)
            .onAppear { if stationID == nil { stationID = initialStationID ?? selected; employeeID = initialEmployeeID; history = initialHistory } }
            .onChange(of: stationID) { _, value in employeeID = value == initialStationID ? initialEmployeeID : nil }
            .safeAreaInset(edge: .bottom) { Button("+ Asignar turno") { assigning = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).padding(16).background(PumaStyle.background).disabled(selected == nil || remote.busy) }
            .sheet(isPresented: $assigning) { if let selected { NavigationStack { ShiftEditorView(stationID: selected, initialDate: max(day, MockDataService.calendar.startOfDay(for: Date()))) } } }
    }
}

func shiftBadge(_ status: String) -> some View { Text(status).font(.caption2.bold()).foregroundStyle(ShiftDisplay.color(status)).padding(5).background(ShiftDisplay.color(status).opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 5)) }

struct ShiftDetailView: View {
    var shiftID: UUID
    @ObservedObject private var store = OperationsStore.shared
    @ObservedObject private var repo = MockDataService.shared
    @ObservedObject private var remote = SupabaseService.shared
    @State private var editing = false
    @State private var confirming = false
    private var shift: WorkShift? { store.data.shifts.first { $0.id == shiftID } }
    var body: some View {
        ScrollView {
            if let shift {
                let employee = store.data.employees.first { $0.id == shift.employeeID }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(ShiftDisplay.code(shift)).font(.caption.bold()); Spacer(); shiftBadge(shift.status) }
                        Text(employee?.name ?? "Empleado").font(.headline)
                        Text("\(employee?.position ?? "") · Empleado \(employee?.active == true ? "activo" : "inactivo")").font(.caption2).foregroundStyle(.secondary)
                    }.pumaCard().overlay(RoundedRectangle(cornerRadius: 12).stroke(PumaStyle.green, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Información del turno").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                        detail("Sucursal", repo.station(id: shift.stationID)?.nombre ?? "")
                        detail("Tipo", shift.type ?? "Personalizado")
                        detail("Inicio", ShiftDisplay.format(shift.start, pattern: "dd/MM/yyyy · HH:mm"))
                        detail("Salida", ShiftDisplay.format(shift.end, pattern: "dd/MM/yyyy · HH:mm") + (ShiftDisplay.overnight(shift) ? " (+1 día)" : ""))
                        detail("Duración", ShiftDisplay.duration(shift))
                        if let time = shift.clockIn { detail("Entrada registrada", ShiftDisplay.format(time, pattern: "dd/MM/yyyy · HH:mm")) }
                        if let time = shift.clockOut { detail("Salida registrada", ShiftDisplay.format(time, pattern: "dd/MM/yyyy · HH:mm")) }
                    }.pumaCard()
                    VStack(alignment: .leading, spacing: 8) { Text("Observaciones").font(.subheadline.bold()).foregroundStyle(PumaStyle.green); Text(shift.notes?.isEmpty == false ? shift.notes! : "Sin observaciones").font(.caption) }.pumaCard()
                    if ShiftDisplay.overnight(shift) { Label("Turno nocturno. Finaliza al día siguiente. Puedes editar o cancelar mientras esté Programado.", systemImage: "info.circle").font(.caption).padding(12).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    if shift.status == "Programado" || shift.status == "En curso" {
                        Button(shift.clockIn == nil ? "Registrar entrada" : "Registrar salida") { Task { _ = await remote.perform { store.clock(shift.id) } } }.buttonStyle(.bordered).disabled(employee?.active != true || remote.busy)
                    }
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(16)
            }
        }.pumaPage().navigationTitle("Detalle del turno").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let shift, shift.isEditable { HStack { Button("Cancelar turno", role: .destructive) { confirming = true }.buttonStyle(.bordered); Button("Editar turno") { editing = true }.buttonStyle(.borderedProminent) }.frame(maxWidth: .infinity).padding(16).background(PumaStyle.background).disabled(remote.busy) }
            }
            .confirmationDialog("¿Cancelar este turno?", isPresented: $confirming, titleVisibility: .visible) { Button("Sí, cancelar turno", role: .destructive) { Task { _ = await remote.perform { store.cancelShift(shiftID) } } } } message: { Text("Se liberará el horario del empleado. El turno se conservará en el historial con estado Cancelado.") }
            .sheet(isPresented: $editing) { if let shift { NavigationStack { ShiftEditorView(stationID: shift.stationID, original: shift, initialDate: ShiftDisplay.date(shift.start)) } } }
    }
    private func detail(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.caption) }
}

struct ShiftEditorView: View {
    var stationID: UUID
    var original: WorkShift?
    var initialDate: Date
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = OperationsStore.shared
    @ObservedObject private var remote = SupabaseService.shared
    @State private var employeeID: UUID?
    @State private var type = "Mañana"
    @State private var date = Date()
    @State private var start = Date()
    @State private var end = Date()
    @State private var notes = ""
    @State private var saved = false
    @State private var error: String?
    private var activeEmployees: [Employee] { store.data.employees.filter { $0.stationID == stationID && $0.active } }
    private var dateAllowed: Bool {
        let unchanged = original?.employeeID == employeeID && original.map { ShiftDisplay.date($0.start) == start && ShiftDisplay.date($0.end) == end } == true
        return unchanged || MockDataService.calendar.startOfDay(for: start) >= MockDataService.calendar.startOfDay(for: Date())
    }
    private var valid: Bool { employeeID != nil && end > start && dateAllowed && activeEmployees.contains { $0.id == employeeID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Turnos · \(original.map(ShiftDisplay.code) ?? "Nuevo turno")").font(.caption).foregroundStyle(PumaStyle.green)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Asignación").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    Text(MockDataService.shared.station(id: stationID)?.nombre ?? "").font(.caption)
                    Picker("Empleado activo *", selection: $employeeID) { Text("Seleccionar empleado").tag(UUID?.none); ForEach(activeEmployees) { Text("\($0.name) · \($0.position)").tag(Optional($0.id)) } }
                    if let employee = activeEmployees.first(where: { $0.id == employeeID }) { Text("Cargo: \(employee.position)").font(.caption) }
                    DatePicker("Fecha de inicio *", selection: $date, in: (original.map { min(ShiftDisplay.date($0.start), MockDataService.calendar.startOfDay(for: Date())) } ?? MockDataService.calendar.startOfDay(for: Date()))..., displayedComponents: .date).onChange(of: date) { _, _ in applyPreset() }
                    if !dateAllowed { Text("No puedes asignar turnos en una fecha pasada.").font(.caption).foregroundStyle(.red) }
                }.pumaCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Horario de trabajo").font(.subheadline.bold()).foregroundStyle(PumaStyle.green)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ShiftDisplay.types, id: \.self) { value in Button { type = value; applyPreset() } label: { VStack { Text(value).font(.caption.bold()); Text(value == "Mañana" ? "06:00–14:00" : value == "Tarde" ? "14:00–22:00" : value == "Noche" ? "22:00–06:00 (+1 día)" : "Definir inicio y fin").font(.system(size: 9)) }.frame(maxWidth: .infinity).padding(10).background(type == value ? PumaStyle.green : PumaStyle.background).foregroundStyle(type == value ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain) }
                    }
                    DatePicker("Fecha y hora inicial *", selection: $start).disabled(type != "Personalizado")
                    DatePicker("Fecha y hora final *", selection: $end).disabled(type != "Personalizado")
                    if end > start { Text("Salida: \(end.formatted(date: .numeric, time: .shortened)) · Duración: \(String(format: "%.1f", end.timeIntervalSince(start) / 3600)) h").font(.caption).foregroundStyle(PumaStyle.green) }
                    else { Text("El fin debe ser posterior al inicio. Revisa fecha y hora.").font(.caption).foregroundStyle(.red) }
                    TextField("Observaciones (opcional)", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)
                }.pumaCard()
                if let error { VStack(alignment: .leading, spacing: 6) { Text("No se pudo guardar el turno").bold(); Text(error); Text("Tus datos se conservan; corrige el horario o vuelve a intentar.") }.font(.caption).foregroundStyle(.red).padding(12).background(Color.red.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8)) }
                if saved { Label("Turno guardado correctamente en Supabase", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(PumaStyle.green).pumaCard() }
            }.padding(16)
        }.pumaPage().navigationTitle(original == nil ? "Asignar turno" : "Editar turno").navigationBarTitleDisplayMode(.inline).environment(\.timeZone, MockDataService.calendar.timeZone)
            .safeAreaInset(edge: .bottom) { HStack { Button("Cancelar") { dismiss() }.buttonStyle(.bordered); Button(saved ? "Volver a turnos" : original == nil ? "Guardar turno" : "Guardar cambios") { if saved { dismiss() } else { Task { await save() } } }.buttonStyle(.borderedProminent).disabled((!valid && !saved) || remote.busy) }.frame(maxWidth: .infinity).padding(16).background(PumaStyle.background) }
            .onAppear { date = initialDate; if let original { employeeID = original.employeeID; type = original.type ?? "Personalizado"; start = ShiftDisplay.date(original.start); end = ShiftDisplay.date(original.end); notes = original.notes ?? "" } else { applyPreset() } }
    }
    private func applyPreset() {
        guard type != "Personalizado" else { return }
        let calendar = MockDataService.calendar, base = calendar.startOfDay(for: date)
        let hour = type == "Mañana" ? 6 : type == "Tarde" ? 14 : 22
        start = calendar.date(byAdding: .hour, value: hour, to: base)!
        end = calendar.date(byAdding: .hour, value: 8, to: start)!
    }
    private func save() async {
        guard let employeeID else { return }
        var shift = WorkShift(id: original?.id ?? UUID(), stationID: stationID, employeeID: employeeID, start: OperationsStore.stamp(start), end: OperationsStore.stamp(end))
        shift.type = type; shift.notes = notes
        error = nil; store.error = nil
        saved = await remote.perform { store.saveShift(shift) }
        if !saved { error = store.error ?? remote.message }
    }
}
