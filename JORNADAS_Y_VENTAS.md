# Jornadas, ventas de empleados y cortes por turno

Implementado en el código móvil y en la capa compartida de la web. La activación en el proyecto remoto requiere ejecutar la migración 004; no se ha ejecutado con la clave pública del cliente. No se ha compilado iOS en este equipo Windows.

## Activación

1. En SQL Editor, confirma que están aplicadas las migraciones 001, 002 y 003. Ejecuta después [004_employee_register.sql](supabase/migrations/004_employee_register.sql). No vuelvas a aplicar las anteriores después de la 004: sustituirían algunas reglas nuevas.
2. Actualiza la app de Xcode y ambas páginas web conjuntamente. El inicio de sesión ahora consulta también las jornadas y ventas compartidas.
3. Desde Personal, registra empleados activos con cargo **Vendedor** o **Despachador**. En su detalle móvil, pulsa **Crear acceso del empleado**. En la web, utiliza **Ventas y cortes por turno → Crear acceso del empleado**. Cada empleado tiene una sola cuenta vinculada.
4. El empleado confirma su correo mediante el enlace recibido. La confirmación de correo continúa siendo necesaria cuando está habilitada en Authentication; no se ha desactivado esta protección.
5. Asigna un horario y selecciona explícitamente **Turno 1** o **Turno 2**. Para horarios anteriores sin número operativo, Mañana se interpreta como turno 1; los demás como turno 2. Conviene revisar las asignaciones futuras existentes.
6. Configura los tres precios por galón en **Ventas y cortes por turno**. No se usan precios de ejemplo para las nuevas ventas.
7. Inicia sesión con cada empleado. Puede registrar entrada durante el horario asignado, vender y registrar salida. El gerente consulta los resúmenes y realiza primero el corte 1 y después el 2.

Web de gerente general: `web-preview/gerente.html` o `web-preview/PUMA-Gerente-General.html`. Preview móvil: `web-preview/index.html` o `web-preview/PUMA-Vista-Previa.html`. Se conservan ambas entradas; el portal general mantiene su navegación agrupada y responde a PC y teléfono.

## Reglas elegidas

- Una jornada por empleado y **día operativo**, según la fecha de inicio en El Salvador. Una jornada nocturna conserva esa fecha después de medianoche. El horario puede ser personalizado; el número de turno operativo se asigna por separado.
- Puede haber varios empleados en un mismo turno de sucursal. Terminar la jornada del empleado y cerrar el turno de la sucursal son acciones distintas. Cerrar sesión conserva la jornada abierta.
- Entrada, venta y salida se validan en el servidor. Repetir entrada o salida devuelve el registro existente. La venta usa un UUID de solicitud que se conserva durante el reintento; el servidor evita repetir esa venta o descontar existencias nuevamente.
- El vendedor solo registra productos; el despachador registra combustible y, opcionalmente, un servicio cobrado. El precio se obtiene del catálogo del servidor. Se aceptan efectivo y tarjeta; tarjeta requiere el importe exacto y efectivo calcula cambio.
- Productos y galones se descuentan **al registrar la venta**. El nuevo corte no vuelve a descontarlos. Los servicios de despacho se registran como completados al cobrar; los servicios de atención diferida conservan su flujo anterior.
- Los cortes guardan combustible, productos y servicios separados; el corte 2 incluye exclusivamente las ventas del turno 2. Cada corte conserva también el acumulado del día existente al cerrarlo. Los resúmenes ya cerrados son inmutables.
- Un corte requiere jornadas registradas y todas las del turno finalizadas. Si un empleado no puede registrar salida, el gerente puede registrar una salida supervisada; el actor queda en auditoría.
- Cada nuevo corte contiene tres controles, uno por combustible. No representan una cantidad de bombas físicas. Los registros históricos de seis lecturas se conservan.
- Los días con capturas manuales anteriores mantienen ese modo. No se mezclan cortes manuales y jornadas nuevas dentro del mismo día: comienza el nuevo flujo en un día operativo sin capturas anteriores. Los borradores previos pueden consultarse y finalizarse por el flujo histórico.
- Los reportes cuentan el combustible directamente desde las nuevas ventas y omiten sus cortes de consolidación. Los productos y servicios se proyectan una sola vez al formato existente, conservando fecha real, empleado, jornada y día operativo. Por eso aparecen también en el dashboard y en los reportes previos.
- Las ventas manuales de gerente ya existentes siguen apareciendo en los reportes. No se atribuyen retroactivamente a empleados ni a turnos; los nuevos cortes operativos usan las ventas vinculadas a jornadas.

Una alternativa futura es añadir un tercer turno operativo, devoluciones autorizadas o servicio pendiente antes del cobro. Requerirían reglas adicionales; esta entrega utiliza los dos turnos y ventas confirmadas que se acordaron.

## Datos y permisos

Las nuevas tablas son `employee_sessions`, `register_sales`, `operational_closures` y `fuel_prices`. RLS permite al empleado consultar su propio historial y al gerente las sucursales que tiene autorizadas. Los empleados no tienen acceso a documentos completos ni a escrituras de catálogo. Las mutaciones se ejecutan mediante funciones transaccionales que usan el mismo bloqueo de sucursal que el almacenamiento anterior.

Las operaciones requieren conexión. Si una respuesta se pierde, reintenta antes de iniciar otra venta y revisa el historial: la base decide qué se guardó. Las vistas consultan cambios cada 30 segundos; no se ha añadido una suscripción Realtime.

Se retiraron los campos y menús de URL/clave del proveedor. Las respuestas técnicas se convierten en mensajes públicos; no se muestra JSON, SQL, tokens ni claves en errores. La clave pública sigue siendo configuración interna del cliente, con seguridad aplicada mediante Auth/RLS. No se incorporó una clave administrativa.

Si se crea una identidad de acceso y luego falla su vinculación al empleado, puede quedar una cuenta sin perfil. Esa identidad no tendrá acceso a datos; el administrador debe revisar Authentication antes de repetir el alta. No se elimina automáticamente una identidad para evitar borrar una cuenta existente.

## Archivos

| Archivos | Motivo |
| --- | --- |
| `Models/User.swift`, `Models/Operations.swift`, `Models/DailyCut.swift` | Roles operativos, jornada, venta, resumen, vínculo de empleado y origen del corte; campos opcionales para conservar documentos anteriores. |
| `Services/SupabaseService.swift` | Lectura compartida, RPC de entrada/venta/salida/corte/precio/alta, rutas por rol y errores públicos. |
| `Services/OperationsStore.swift`, `Services/MockDataService.swift` | Una asignación diaria, observación de ventas y compatibilidad de tres controles con seis registros anteriores. |
| `App/RootView.swift`, `Views/OperationsView.swift`, `Views/ShiftScheduleView.swift` | Pantallas exclusivas de empleado, alta de acceso, filtros del gerente, resúmenes y selección del turno operativo. |
| `ViewModels/GeneralManagerViewModel.swift`, `ViewModels/BranchManagerViewModel.swift` | Combustible en vivo y prevención del doble conteo; productos y servicios continúan en el reporte existente. |
| `Views/BranchManager/BMDashboardView.swift`, `Views/BranchManager/CutFormView.swift` | Acceso al nuevo corte, dashboard comercial y consulta del historial. |
| `Views/LoginView.swift`, `Views/GeneralManager/AddStationView.swift`, `Views/GeneralManager/StationManagementView.swift` | Mensajes públicos y descripción correcta de los controles. |
| `web-preview/{app,domain,operations,modules,shifts,supabase,gerente}.js` | Mismos roles, filtros, RPC, reportes y reglas en la web y preview. |
| `supabase/migrations/004_employee_register.sql` | Tablas, permisos, transacciones, idempotencia e integración con documentos históricos. |
| `supabase/tests/employee_register.sql` | Pruebas con rollback de permisos, pagos, inventario, reintentos y separación de los dos cortes. |
| `web-preview/{domain,operations,ui}.test.js`, `PumaGasStationTests/BusinessRulesTests.swift` | Regresión de historial, permisos de interfaz, errores públicos, límite diario y reportes sin duplicación. |
| `web-preview/PUMA-Gerente-General.html`, `web-preview/PUMA-Vista-Previa.html` | Paquetes web regenerados con los cambios. |

## Verificación

Verificados en este equipo: **49 pruebas JavaScript aprobadas**, estructura del proyecto Xcode y `git diff --check` sin errores. Ejecuta `python scripts/test_web.py` y `python scripts/verify_project.py`. En Mac, compila el esquema PumaGasStation y ejecuta PumaGasStationTests. En SQL Editor, ejecuta `supabase/tests/employee_register.sql` después de la migración: termina con rollback y comprueba ambos turnos, totales y permisos.

La prueba real entre dos cuentas y los dos clientes sigue pendiente de aplicar la migración y disponer de cuentas confirmadas. Las pruebas JavaScript usan un servidor simulado; no prueban el proyecto remoto. El guion SQL está preparado, pero no se ha ejecutado aquí porque no hay PostgreSQL ni acceso administrativo.
