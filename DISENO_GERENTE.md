# Adaptación de la exportación Gerente

Referencia: imagen `Gerente.png` proporcionada por el usuario. No se obtuvo acceso al archivo de Figma ni a sus medidas, variables o recursos originales; el resultado es una adaptación visual, no una reproducción verificada píxel a píxel. No se usa la imagen como fondo de la aplicación.

## Pantallas y archivos

| Módulo | Adaptación | Archivos |
| --- | --- | --- |
| Personal | Lista compacta, estado, búsqueda, filtros, detalle, datos laborales, acceso a turnos y edición agrupada | `PumaGasStation/Views/OperationsView.swift`, `web-preview/modules.js` |
| Inventario comercial | Categorías, búsqueda, precio, alertas y distintivos de existencias; acceso al punto de venta e historial | Los mismos archivos |
| Punto de venta | Productos, carrito, total, pago, confirmación después del servidor; historial compacto y detalle de artículos y cambio | Los mismos archivos |
| Servicios | Catálogo separado del historial; disponibilidad, registro, detalle y transiciones; presión opcional para servicios cuyo nombre contiene «aire» | Los mismos archivos |
| Turnos | Se conserva programación, detalle, edición, cancelación y validaciones; el acceso desde un empleado selecciona su sucursal y empleado | `PumaGasStation/Views/ShiftScheduleView.swift`, interfaz existente `web-preview/shifts.js` |
| Llenar tanques | Tarjetas de inventario, registro independiente e historial, con el estilo verde y fondo gris de los otros módulos | `OperationsView.swift`, `modules.js` |
| Estilos web | Tarjetas, distintivos, formularios agrupados, resumen, carrito y confirmación | `web-preview/styles.css` |

Los componentes SwiftUI nuevos permanecen en `OperationsView.swift`, ya registrado en Xcode. Se reutilizan `PumaStyle`, `pumaCard` y `pumaPage`; no se agregan dependencias ni se modifica el esquema de datos. `web-preview/PUMA-Vista-Previa.html` se regenera con el mismo código.

## Decisiones y límites

- No aparece una pantalla específica de llenar tanques en la exportación; se adapta el lenguaje visual común.
- Se mantiene `Employee.name` como nombre completo. Separar nombre y apellidos requeriría acordar la migración de los registros existentes.
- Los códigos de pantalla se derivan de UUID existentes; no se inventan secuencias como EMP-001 o V-00128 que podrían colisionar entre clientes.
- La presión PSI se conserva en observaciones; crear campos estructurados por tipo de servicio sería una ampliación del modelo.
- En móvil se mantienen navegación nativa y formularios en hojas; en web se mantienen los editores en diálogos. Listados y detalles sí se separan como en el prototipo.
- Se conservan los montos en USD y la zona horaria de El Salvador que usa el proyecto. El prototipo contiene otras ubicaciones/moneda; esos textos no reemplazan los datos reales del negocio.
- Ninguna confirmación de venta se muestra antes de la respuesta satisfactoria de Supabase. La creación y actualización continúan usando las validaciones y permisos existentes.

## Verificación

41 pruebas JavaScript aprobadas, incluyendo navegación/render de detalle de personal, inventario, carrito, confirmación de venta y detalle de servicio. Son pruebas con DOM y REST simulados; no sustituyen una inspección visual ni una sesión autenticada real.

La estructura del proyecto Xcode pasa la verificación de referencias y archivos. Este entorno Windows no permite compilar SwiftUI ni ejecutar el simulador. El navegador automatizado disponible falla al iniciar, por lo que resta revisar visualmente la web y el simulador en el equipo de desarrollo.
