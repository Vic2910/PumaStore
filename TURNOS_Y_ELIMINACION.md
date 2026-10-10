# Turnos e eliminación de gerentes

## Activación en Supabase

Ejecuta `supabase/migrations/003_shift_history_manager_delete.sql` en SQL Editor, después de las migraciones 001 y 002. Es repetible y se ejecuta dentro de una transacción. Si vuelves a ejecutar 002, ejecuta 003 después para restaurar la validación nueva.

Esta migración está preparada, **no ejecutada en tu servidor**: la clave pública no permite instalar funciones SQL. Hasta que la ejecutes, la eliminación remota no estará habilitada y la protección de fechas pasadas existirá únicamente en los clientes.

## Comportamiento

- No se pueden crear turnos ni cambiar empleado/horario a una fecha anterior a hoy en El Salvador. Se permite hoy, aunque la hora de inicio ya haya pasado: el requerimiento se interpreta como restricción de fecha, no de hora. Si se requiere bloquear también horas anteriores, puede endurecerse después.
- Los turnos antiguos se conservan y pueden consultarse. Cambiar solo observaciones de un turno todavía Programado o cancelar uno no modifica su asignación histórica. Iniciados/completados/cancelados conservan las restricciones previas.
- En Turnos se puede alternar Programación por fecha e Historial completo, filtrando sucursal, empleado y estado. Incluye empleados inactivos, entradas/salidas y turnos cancelados. Desde Personal → Detalle → Consultar turnos e historial se abre directamente el empleado seleccionado. Las entradas muestran fecha y se ordenan de más reciente a más antigua.
- El gerente general dispone de Eliminar gerente, con confirmación. La función SQL acepta solo perfiles de sucursal y solo un general activo puede ejecutarla. Elimina el perfil, libera la sucursal y actualiza su nombre y revisión con auditoría. Funciona para gerentes activos, inactivos y sin asignación.
- El usuario técnico de **Supabase Auth no se borra**, porque puede estar referenciado por datos históricos. Sin perfil no puede entrar a la aplicación ni leer/escribir sucursales con RLS, incluso si conserva un token anterior. La supresión completa de Auth requeriría un proceso administrativo en servidor y revisar esas referencias; no se introduce una clave administrativa en los clientes.

## Archivos modificados

| Archivos | Motivo |
| --- | --- |
| `PumaGasStation/Services/OperationsStore.swift`, `web-preview/operations.js` | Validación de fechas y eliminación local usada exclusivamente en pruebas. |
| `PumaGasStation/Views/ShiftScheduleView.swift`, `web-preview/shifts.js` | Historial por empleado y feedback de fecha inválida. |
| `PumaGasStation/Views/OperationsView.swift`, `web-preview/modules.js` | Acceso al historial desde el detalle del empleado. |
| `PumaGasStation/Services/SupabaseService.swift`, `web-preview/supabase.js` | Eliminación remota y actualización de datos después de confirmación del servidor. |
| `PumaGasStation/Views/GeneralManager/StationManagementView.swift`, `web-preview/app.js` | Botón Eliminar gerente, confirmación y errores. |
| `supabase/migrations/003_shift_history_manager_delete.sql` | Validación en servidor y RPC protegida para eliminar el perfil. |
| Pruebas Swift y JavaScript | Ayer rechazado, hoy permitido, preservación del historial y eliminación de gerente. |

## Verificación

44 pruebas JavaScript aprobadas. Estructura de Xcode validada. No se han ejecutado XCTest ni esta migración en Supabase; tampoco se ha comprobado visualmente el simulador en este entorno Windows. Los archivos web empaquetados se regeneran para incluir los cambios en preview y portal general.
