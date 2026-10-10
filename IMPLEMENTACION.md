# Entrega de PUMA: turnos y base compartida

## Diagnóstico y cambio de flujo

El código original tenía MVVM SwiftUI, repositorios JSON/Keychain y una web equivalente con almacenamiento local. La primera ampliación añadía conexión remota opcional y publicación manual. Eso permitía guardar localmente sin que móvil y web compartieran el cambio.

Ahora el login normal utiliza Supabase Auth. Los formularios de ambas plataformas esperan confirmación del servidor al guardar; se eliminó la publicación manual como requisito de trabajo. Los repositorios locales permanecen como caché y como soporte de pruebas, no como fuente independiente de datos operativos. El cliente web empieza vacío, sin cuentas de demostración; el singleton iOS no genera ejemplos en una instalación nueva.

Las tablas están presentes en el Supabase proporcionado. La comprobación real devolvió Auth HTTP 200, tabla `station_documents` protegida con HTTP 401 para anon y función `save_stations` existente. La consulta pública denegada es normal: no conceder SELECT a anon. El usuario confirmó que ejecutó el SQL inicial y está creando las cuentas. No se dispuso de una sesión autenticada para probar datos reales de extremo a extremo.

## Turnos: diseño y comportamiento

- Programación con sucursal, fecha, empleado, estado y cuatro contadores; tarjetas de empleado/puesto/horario/duración y aviso de salida al día siguiente.
- Asignación con empleado activo, puesto derivado del empleado, fecha, observaciones y presets Mañana 06:00–14:00, Tarde 14:00–22:00, Noche 22:00–06:00 del día siguiente, o fechas/horas personalizadas.
- Detalle con identidad, información, observaciones, entrada/salida y aviso nocturno.
- Edición/cancelación exclusivamente en estado Programado. Cancelar requiere confirmación, conserva historial y libera el horario. La baja del empleado no borra turnos anteriores y bloquea nuevas asignaciones/marcaciones.
- Programado = sin entrada; En curso = entrada registrada; Completado = salida registrada; Cancelado = baja lógica. No se asume asistencia solo por la hora del reloj.
- Fin posterior al inicio, empleados activos y solapamientos se validan en clientes y servidor. Los turnos cancelados se excluyen del conflicto. La edición conserva identificador, historial y sucursal. Fecha/hora se interpretan en El Salvador (UTC−6).
- Si guardar falla, no se cierra el formulario ni se muestra éxito. Se conservan valores y se permite reintentar. Un conflicto de revisión actualiza datos compartidos y requiere revisar el formulario antes del reintento.

Se mantienen navegación, verde PUMA, fondo gris y tarjetas existentes. El detalle usa pantallas dedicadas como la referencia; en iOS el editor se presenta dentro de NavigationStack en una hoja. Esa es la interpretación más simple compatible con la navegación previa. El puesto no se edita dentro del turno: se administra en Personal. No hay archivo Figma editable disponible ni comparación píxel a píxel verificada.

## Datos y autorización

`station_documents` contiene el documento compartido de cada sucursal: combustible/cortes y operaciones. `profiles` vincula Auth con rol, sucursal y estado; `station_audit` conserva revisiones. General accede a todas las sucursales; gerente de sucursal solo a la asignada; cuentas inactivas no acceden.

`save_stations` guarda todas las sucursales afectadas por una operación en una sola transacción y devuelve revisiones. La revisión antigua se rechaza. La migración 002 añade validaciones de turnos, bajas históricas y administración de gerentes; bloquea la llamada directa al endpoint anterior para que clientes usen la validación nueva. Se revocan explícitamente los permisos anónimos que Supabase puede conceder por defecto.

Web calcula el próximo estado sin alterar los datos visibles y lo aplica después de recibir confirmación. iOS toma un snapshot, ejecuta la regla local existente, publica automáticamente y restaura la caché si falla. Las pantallas esperan esa operación antes de cerrar. Ambos clientes renuevan tokens expirados y actualizan datos cada 30 segundos; web pausa la actualización durante edición de cortes/turnos y diálogos. Una cuenta desactivada se bloquea en servidor inmediatamente y se cierra en cliente al actualizar su perfil.

Crear gerente registra su correo/contraseña en Auth y provisiona el perfil mediante RPC autorizada al general; conserva la sesión del general. Reasignar, desactivar y reactivar modifican los perfiles remotos y la asignación de la sucursal. Si está habilitada la confirmación de correo, el gerente debe confirmarlo. Solo el primer general se crea y vincula desde el panel usando `bootstrap_general.sql`.

Capacidad inicial sigue en **10,000 galones**, no existencias iniciales: una sucursal nueva inicia vacía. Recomiendo capacidad administrativamente editable según el tanque físico certificado; no se ha añadido formulario para cambiarla. Personal usa bajas lógicas; ventas descuentan existencias y conservan precio histórico; servicios mantienen catálogo y ejecución independiente. Los reportes originales describen combustible, no consolidación contable de todas las líneas de negocio.

## Archivos relevantes

| Archivo | Motivo |
| --- | --- |
| `PumaGasStation/Views/ShiftScheduleView.swift` (nuevo) | Listado/filtros/contadores, detalle, asignación, edición y cancelación de turnos. |
| `PumaGasStation/Models/Operations.swift` | Tipo, observaciones, cancelación y estado derivado compatibles con datos anteriores. Modelos de los demás módulos. |
| `PumaGasStation/Services/OperationsStore.swift` | Validación de edición/cancelación y conflictos; restauración de caché; reglas de personal, comercio, servicios y llenado. |
| `PumaGasStation/Services/SupabaseService.swift` | Guardado automático transaccional, renovación de token, refresco, perfiles y acciones sobre gerentes. |
| `PumaGasStation/Views/OperationsView.swift` | Conecta todos los formularios al servidor; navegación al nuevo flujo de turnos. |
| `PumaGasStation/ViewModels/AuthViewModel.swift`, `Views/LoginView.swift` | Login normal por correo/Auth; elimina acceso local del flujo operativo. |
| `PumaGasStation/App/RootView.swift` | Menú Más y bloqueo/indicador durante operaciones de red. |
| `PumaGasStation/ViewModels/BranchManagerViewModel.swift`, `Views/BranchManager/CutFormView.swift` | Cortes y cambios de turno esperan confirmación remota; llenados separados. |
| `PumaGasStation/Views/GeneralManager/AddStationView.swift` | Alta de sucursal confirmada por servidor. |
| `PumaGasStation/Views/GeneralManager/AddManagerView.swift`, `StationManagementView.swift` | Creación Auth, reasignación y baja/reactivación reales. |
| `PumaGasStation/Services/MockDataService.swift` | Caché, capacidades/migración, sin ejemplos en nueva instalación normal. |
| `PumaGasStation/Models/Station.swift`, `Models/User.swift`, `ViewModels/GeneralManagerViewModel.swift`, `Views/BranchManager/BMDashboardView.swift` | Historial de llenados, compras coherentes, estado de usuarios y reportes originales. |
| `PumaGasStation/Views/GeneralManager/StationDetailView.swift` | Preview seguro sin asumir datos locales de ejemplo. |
| `PumaGasStation.xcodeproj/project.pbxproj` | Registro de las fuentes nuevas en grupos y target. |
| `PumaGasStationTests/BusinessRulesTests.swift` | Pruebas de capacidades, bajas, ventas y cancelación/liberación de horarios. |
| `web-preview/shifts.js` (nuevo), `styles.css` | Flujo y diseño web de turnos siguiendo la referencia. |
| `web-preview/app.js`, `modules.js`, `supabase.js` | Login Auth y guardado automático de todos los módulos, caché tras confirmación, manejo de errores y perfiles. |
| `web-preview/domain.js`, `operations.js` | Reglas de combustible y nuevos módulos, estados/cancelación de turnos. |
| `web-preview/index.html`, `build-preview.py`, `PUMA-Vista-Previa.html` | Aplicación conectada, carga y empaquetado actualizado. |
| `web-preview/operations.test.js`, `ui.test.js`, `scripts/test_web.py` | Pruebas de negocio, red, render y flujo de turnos. |
| `supabase/migrations/001_shared_store.sql`, `002_automatic_operations.sql` | Esquema inicial, RPC, RLS, transacciones y validación de turnos. |
| `supabase/bootstrap_general.sql` (nuevo) | Vincula el primer correo Auth con perfil general desde SQL Editor. |
| `supabase/tests/automatic_operations.sql` (nuevo) | Pruebas SQL con ROLLBACK de permisos, concurrencia y turnos. |
| `supabase/client-config.json`, `scripts/check_supabase.py` | Configuración pública y diagnóstico no mutante de conexión. |
| `README.md`, `web-preview/README.md`, `PUESTA_EN_MARCHA.md`, `IMPLEMENTACION.md` | Instrucciones y estado de entrega actualizado. |

## Verificación y límites

- **41 pruebas JavaScript** pasan: negocio, estados/solapamientos, render de pantallas, Auth y renovación simulados, confirmación remota, rechazo de sesión ausente y conservación de datos ante error. REST y DOM de estas pruebas son simulados.
- Proyecto Xcode estructuralmente válido: 95 objetos PBX y 27 fuentes Swift, referencias, scheme y assets verificados. No equivale a compilar.
- Compilación/XCTest: pendientes; Windows no tiene Xcode/iOS SDK. Se añadieron pruebas Swift para ejecutar en macOS.
- Navegador real: la herramienta falló al inicializar; comparación visual pendiente. Las pantallas no se certifican píxel a píxel.
- SQL/RLS: se entregan pruebas ejecutables, pero no se ejecutaron con permisos administrativos en el servidor desde aquí. El usuario debe ejecutar la versión final de 002 y bootstrap.
- Auth real y sincronización entre dispositivos: requiere la cuenta inicial y un recorrido autenticado. No se afirma que esa prueba haya pasado sin sesión real disponible.
- No hay funcionamiento operativo offline: errores de conexión dejan el formulario pendiente. Caché y credenciales de sesión no sustituyen autorización del servidor.
- Si se pierde la conexión justo después de que el servidor confirme internamente y antes de recibir respuesta, revisar el historial antes de repetir una venta/llenado. No se añadió una clave de idempotencia por solicitud.
- La creación de una cuenta Auth y su perfil son dos operaciones: si el provisionamiento falla después de crear Auth, queda una cuenta sin acceso; debe vincularse desde el panel o resolver el error. La comprobación de RPC se hace antes de registrar para evitar el caso habitual de migración faltante.
- La base por documentos evita reescribir la arquitectura, pero no normaliza todas las tablas ni recalcula todas las reglas comerciales frente a un cliente manipulado. Para producción conviene RPC especializadas para inventario/ventas, pruebas de seguridad completas y seguimiento de auditoría.
- iOS conserva caché en dos archivos, cada uno atómico; no hay transacción de filesystem entre ambos. El servidor sí confirma la operación de base en una sola transacción.

La configuración Auth/RLS se basa en documentación oficial: https://supabase.com/docs/guides/auth y https://supabase.com/docs/guides/database/postgres/row-level-security.
