# Análisis de rendimiento integral

La pantalla de reportes móvil y web muestra ingresos de combustible, productos de conveniencia/lubricantes y servicios. Conserva el estilo y la navegación existentes.

El dashboard del **gerente general** también muestra los ingresos totales de hoy y tres tarjetas de combustible, productos y servicios. Añade unidades de productos vendidos y servicios completados y pendientes/en proceso registrados hoy, con accesos al punto de venta y servicios. El filtro de sucursal se aplica a todos estos indicadores. La comparación entre sucursales usa ingresos totales **de hoy** (antes mostraba combustible acumulado). Compras, galones y pérdidas mantienen sus medidas de combustible. Se reutiliza la agregación del reporte, sin nuevas escrituras ni migraciones.

- Filtros por sucursal, período (7, 30, 90 o 365 días, incluyendo hoy) y actividad.
- Total general y desglose por actividad. El filtro de actividad cambia la tendencia, el indicador seleccionado y los detalles; el total general conserva su desglose para dar contexto.
- Comparación de la actividad seleccionada con los días inmediatamente anteriores, sin solapamiento. Cuando el período anterior es cero se indica «Sin base de comparación».
- Combustible: ingresos por tipo, galones vendidos y pérdidas.
- Productos: unidades y cinco productos con más ingresos, usando los importes guardados en las ventas, incluso si cambia el catálogo.
- Servicios: completados, pendientes/en proceso y cancelados; cinco servicios con más ingresos completados.
- CSV diario con todos los desgloses, total general, ingresos de la actividad seleccionada y contadores separados. Incluye días sin actividad.

## Criterio de reconocimiento

Solo se suman cortes cerrados, ventas comerciales confirmadas y servicios con estado `Completado`. Compras, llenados, servicios cancelados, pendientes o en proceso no se suman a ingresos. No se combinan galones, unidades y servicios como un volumen único.

Se utiliza el calendario de El Salvador (UTC−6). Los servicios completados se atribuyen a **su fecha de registro**, porque el modelo actual no guarda fecha de finalización ni cobro. Los contadores de pendientes describen registros creados dentro del período, no todo el trabajo pendiente histórico. Una alternativa futura es guardar `completedAt` y pago del servicio para analizar ingresos por fecha de prestación/cobro. Cambiar el estado de un servicio antiguo a completado actualiza el período de su registro.

Los montos representan ingresos operativos, **no utilidad ni un reporte contable de cobros**. No se estima utilidad con costos actuales del catálogo: faltan costos históricos uniformes para las tres actividades. No se requiere una migración de Supabase; se leen los mismos registros sincronizados y se mantienen los permisos existentes.

## Archivos

| Archivo | Cambio |
| --- | --- |
| `PumaGasStation/ViewModels/GeneralManagerViewModel.swift` | Agregación diaria, detalles, comparación, CSV y observación de `OperationsStore` para recibir cambios remotos. Permite inyectar el almacén en pruebas. |
| `PumaGasStation/Views/GeneralManager/GMDashboardView.swift` | Pantalla `PerformanceView` con filtros, desglose, detalles, comparación y exportación actualizada. |
| `web-preview/operations.js` | Funciones puras `performance` y `performanceCSV`; no mutan los datos ni escriben en Supabase. |
| `web-preview/app.js` | Render de reportes, filtros, comparación y descarga del CSV con los criterios actuales. |
| `web-preview/operations.test.js`, `web-preview/ui.test.js` | Pruebas de sumas, límites del calendario, filtros, precios históricos, CSV y render. |
| `PumaGasStationTests/BusinessRulesTests.swift` | Prueba equivalente de ingresos, exclusiones y actualización observable en Swift. |
| `web-preview/PUMA-Vista-Previa.html` | Versión autónoma regenerada. |

## Verificación

44 pruebas JavaScript aprobadas. La estructura y referencias del proyecto Xcode pasan la verificación. SwiftUI y XCTest no se pueden compilar/ejecutar en este entorno Windows. El render web se prueba con DOM simulado; queda pendiente revisión visual y prueba con sesión real en ambos clientes. La disponibilidad de datos reales depende de la configuración de Auth y las migraciones ya documentadas en `PUESTA_EN_MARCHA.md`.
