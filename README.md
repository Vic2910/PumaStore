# PUMA · Gestión de franquicia

Aplicación SwiftUI iOS 17+ y aplicación web, con datos compartidos en Supabase. Abre `PumaGasStation.xcodeproj`, esquema **PumaGasStation**, en Xcode. No requiere paquetes Swift externos.

**El acceso normal usa correo y contraseña de Supabase Auth.** Se retiró el login local de demostración del flujo de producción. Cada guardado espera confirmación del servidor; no hace falta pulsar Publicar. Se incluyen sucursales, gerentes, combustible/cortes, personal, turnos, productos, ventas y servicios.

Consulta [PUESTA_EN_MARCHA.md](PUESTA_EN_MARCHA.md) para terminar la instalación: ejecutar la versión final de la migración 002, crear la cuenta inicial en Auth y vincular su perfil general. Las tablas y la función de guardado ya responden en tu proyecto; no se ha verificado una sesión real porque aún no se proporcionó acceso a una cuenta.

## Turnos

El diseño sigue la referencia: programación con filtros y contadores; asignación, detalle y edición; horarios mañana, tarde, noche y personalizado; observaciones, validación de empleados activos y solapamientos; cancelación confirmada que conserva historial y libera horario. Los estados se basan en marcaciones reales, no en suponer que el empleado trabajó por haber llegado la hora.

## Web

Ejecuta `python -m http.server 8765 --bind 127.0.0.1 --directory web-preview` y abre `http://127.0.0.1:8765`. También puedes abrir `web-preview/PUMA-Vista-Previa.html`; para usar Auth y caché de forma consistente se recomienda el servidor local. Consulta [web-preview/README.md](web-preview/README.md).

## Comprobaciones

- `python scripts/test_web.py`: 44 pruebas JavaScript de negocio, render HTML, Auth/REST simulados, guardado automático y errores de red.
- `python scripts/verify_project.py`: PBX, scheme y assets válidos; 27 archivos Swift registrados.
- `python web-preview/build-preview.py`: regenera el HTML autónomo.
- `python scripts/check_supabase.py`: comprobaciones no mutantes de Auth, permisos anónimos y existencia del endpoint de guardado.
- `supabase/tests/automatic_operations.sql`: pruebas transaccionales de servidor para ejecutar en SQL Editor; termina con ROLLBACK. No ejecutadas aquí.

La compilación/XCTest y revisión visual en iPhone requieren macOS/Xcode. No se certifica todavía compilación ni fidelidad píxel a píxel. Consulta [IMPLEMENTACION.md](IMPLEMENTACION.md) para arquitectura, archivos modificados y límites.


Implementacion de jornadas y ventas de empleados: [JORNADAS_Y_VENTAS.md](JORNADAS_Y_VENTAS.md). Incluye la migracion 004, permisos, activacion y pruebas.
