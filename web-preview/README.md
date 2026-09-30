# Vista previa web de PUMA

Esta versión permite explorar desde Windows las pantallas y las reglas de negocio del proyecto. Es una implementación equivalente en HTML/CSS/JavaScript: no ejecuta SwiftUI, no utiliza el SDK de iOS y no confirma que el proyecto Xcode compile.

## Abrir sin instalar nada

Abre `PUMA-Vista-Previa.html` con Edge, Chrome o Firefox. Incluye todos los estilos, scripts y el logo. No necesita conexión a internet ni servidor. Si el navegador restringe el almacenamiento de archivos locales, usa la versión servida como se describe abajo.

Se puede entrar con los botones de Gerente General y Gerente de Sucursal, o con las cuentas del proyecto (`gerente.general`, `santa.ana`, `san.salvador`, `sonsonate`; contraseña `1234`). Las credenciales son exclusivamente de demostración. No introduzcas credenciales reales: esta vista previa no ofrece la seguridad de un sistema de autenticación remoto y guarda los usuarios de prueba en el navegador.

## Abrir con servidor local

Desde la raíz del proyecto, ejecuta:

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory web-preview
```

Abre `http://127.0.0.1:8765`. El servidor solo escucha en tu equipo. Mantén la terminal abierta mientras utilizas esa dirección; Ctrl+C lo detiene. La versión servida y el archivo autónomo tienen almacenes separados.

## Prueba rápida

1. Entra como Gerente de Sucursal y abre Capturar Corte. El matutino inicial está cerrado; el vespertino está pendiente.
2. Intenta cerrar sin registrar las seis bombas: el sistema debe rechazarlo.
3. En cada bomba registra 10 galones, un monto de $40 y marca la casilla registrada. Total esperado: 60 galones y $240.
4. Añade una recepción de Súper de 100 galones por $300 y una pérdida de Súper de 5 galones.
5. Guarda el borrador: ni inventario ni totales consolidados deben cambiar.
6. Cierra el corte. En Santa Ana el inventario esperado es Súper 7,275 gal, Regular 4,480 gal y Diésel 1,780 gal.
7. Entra como Gerente General. Las ventas globales iniciales son $6,536.80 y después del corte deben ser $6,776.80. Santa Ana queda con 2/2 cortes cerrados.
8. Recarga la página, entra otra vez y comprueba que se conservaron los datos.

Los cortes se agrupan por fecha de El Salvador. Si realizas la prueba otro día después de guardar los ejemplos, las métricas de hoy cambian porque los cortes anteriores pasan al historial. Reiniciar los datos desde el panel vuelve a crear ejemplos para la fecha actual; esa operación reemplaza los cambios de demostración.

## Alcance

- Ambos perfiles, navegación inferior, sucursales, alta y detalle, gerentes y reasignación, reportes y CSV.
- Seis bombas individuales, dos cortes por fecha, compras, pérdidas, borradores y cierres inmutables.
- Cierre transaccional: existencias + compras − ventas − pérdidas. Se rechazan valores negativos, no finitos y movimientos fuera de la capacidad.
- Tanques globales ponderados por capacidad y alertas individuales.
- Inventario, historial de recepciones y solicitudes descargables para compartir. No envía pedidos a proveedores.
- Guardado local. No hay sincronización con el proyecto SwiftUI, con otros dispositivos ni entre navegadores.

Se conservan galones y los umbrales del proyecto: crítico <25%, medio <60%, óptimo >=60%. No se incluyen servicios de mantenimiento ni productos ajenos al combustible.

## Verificación

Ejecuta `node --test web-preview/domain.test.js` desde la raíz del proyecto. Las 15 pruebas pasaron en Windows. Se probó además desde el navegador el bloqueo de cierre incompleto, captura de seis bombas, compra, pérdida, guardado, cierre, inventario, consolidación, persistencia al recargar, alta/búsqueda de sucursales, detalle y períodos de reportes. No hubo errores de consola en ese recorrido. Estas pruebas validan esta versión web, no el binario iOS.

`domain.js` contiene las reglas; `app.js` controla las vistas y la interacción; `styles.css` define la presentación. Después de editarlos, ejecuta `python web-preview/build-preview.py` para actualizar el archivo autónomo.
